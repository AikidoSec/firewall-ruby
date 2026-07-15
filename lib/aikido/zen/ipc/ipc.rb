# frozen_string_literal: true

require "openssl"
require "securerandom"
require "socket"
require "concurrent"

# Code coverage is disabled here because `OpenSSL.fixed_length_secure_compare`
# is already defined in the normal case.
# :nocov:
unless OpenSSL.respond_to?(:fixed_length_secure_compare)
  def OpenSSL.fixed_length_secure_compare(a, b)
    l = a.unpack("C#{a.bytesize}")

    res = 0
    b.each_byte { |byte| res |= byte ^ l.shift }
    res == 0
  end
end
# :nocov:

module Aikido
  module Zen
    module IPC
      CONNECT_TIMEOUT = 2.0
      HANDSHAKE_TIMEOUT = 3.0
      READ_TIMEOUT = 5.0
      WRITE_TIMEOUT = 5.0

      RECONNECT_DELAY = 1.0

      module TimedIO
        private

        def connect_with_deadline(host, port, deadline)
          socket = ::Socket.new(:INET, :STREAM)

          addr = ::Socket.sockaddr_in(port, host)

          connected = false

          case socket.connect_nonblock(addr, exception: false)
          # Code coverage is disabled here because this is hard to control.
          # :nocov:
          when 0
            connected = true
          # :nocov:
          when :wait_writable
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)

            # Code coverage is disabled here because this is hard to control.
            # :nocov:
            unless remaining > 0 && ::IO.select(nil, [socket], nil, remaining)
              raise Errno::ETIMEDOUT, "connect timed out"
            end
            # :nocov:

            errno = socket.getsockopt(::Socket::SOL_SOCKET, ::Socket::SO_ERROR).int

            unless errno == 0
              raise SystemCallError.new(errno)
            end

            connected = true

          # Code coverage is disabled here because this code is unreachable.
          # :nocov:
          else
            # empty
          end
          # :nocov:

          socket
        ensure
          socket.close unless connected
        end

        def connect_with_timeout(host, port, timeout)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

          connect_with_deadline(host, port, deadline)
        end

        def read_with_deadline(socket, length, deadline, buffer: String.new(encoding: Encoding::BINARY), chunk_size: 0)
          while buffer.bytesize < length
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)

            raise Errno::ETIMEDOUT, "read timed out" unless remaining > 0

            read_size = [chunk_size, length - buffer.bytesize].max

            case chunk = socket.read_nonblock(read_size, exception: false)
            # Code coverage is disabled here because this is hard to control.
            # :nocov:
            when :wait_readable
              raise Errno::ETIMEDOUT, "read timed out" unless ::IO.select([socket], nil, nil, remaining)
            # :nocov:
            when nil
              raise EOFError
            else
              buffer << chunk
            end
          end

          buffer
        end

        def write_with_deadline(socket, data, deadline)
          written = 0

          while written < data.bytesize
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)

            raise Errno::ETIMEDOUT, "write timed out" unless remaining > 0

            case n = socket.write_nonblock(data.byteslice(written..), exception: false)
            # Code coverage is disabled here because this is hard to control.
            # :nocov:
            when :wait_writable
              raise Errno::ETIMEDOUT, "write timed out" unless ::IO.select(nil, [socket], nil, remaining)
            # :nocov:
            else
              written += n
            end
          end
        end
      end

      module FramedIO
        include TimedIO

        READ_CHUNK_SIZE = 65536

        class FrameTooLargeError < StandardError
          def initialize(size, max_size)
            super("frame too large: #{size} bytes (max: #{max_size})")
          end
        end

        private

        def read_frame_with_deadline(socket, max_size, deadline, buffer: String.new(encoding: Encoding::BINARY), chunk_size: 0)
          read_with_deadline(socket, 4, deadline, buffer: buffer, chunk_size: chunk_size)

          size = buffer.byteslice(0, 4).unpack1("N")

          if max_size && size > max_size
            raise FrameTooLargeError.new(size, max_size)
          end

          read_with_deadline(socket, 4 + size, deadline, buffer: buffer, chunk_size: chunk_size)

          buffer.byteslice(4, size)
        end

        def read_frame_with_timeout(socket, max_size, timeout, buffer: String.new(encoding: Encoding::BINARY), chunk_size: 0)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

          read_frame_with_deadline(socket, max_size, deadline, buffer: buffer, chunk_size: chunk_size)
        end

        def read_coalesced_frame_with_deadline(socket, buffer, max_size, deadline, chunk_size: READ_CHUNK_SIZE)
          frame = read_frame_with_deadline(socket, max_size, deadline, buffer: buffer, chunk_size: chunk_size)

          buffer.replace(buffer.byteslice((4 + frame.bytesize)..))

          frame
        end

        def read_coalesced_frame_with_timeout(socket, buffer, max_size, timeout, chunk_size: READ_CHUNK_SIZE)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

          read_coalesced_frame_with_deadline(socket, buffer, max_size, deadline, chunk_size: chunk_size)
        end

        def write_frame_with_deadline(socket, data, max_size, deadline)
          bytes = data.b

          if max_size && bytes.bytesize > max_size
            raise FrameTooLargeError.new(bytes.bytesize, max_size)
          end

          write_with_deadline(socket, [bytes.bytesize].pack("N"), deadline)
          write_with_deadline(socket, bytes, deadline)
        end

        def write_frame_with_timeout(socket, data, max_size, timeout)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

          write_frame_with_deadline(socket, data, max_size, deadline)
        end

        def write_coalesced_frame_with_deadline(socket, data, max_size, deadline)
          size = data.bytesize

          if max_size && size > max_size
            raise FrameTooLargeError.new(size, max_size)
          end

          frame = [size].pack("N")
          frame << data

          write_with_deadline(socket, frame, deadline)
        end

        def write_coalesced_frame_with_timeout(socket, data, max_size, timeout)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

          write_coalesced_frame_with_deadline(socket, data, max_size, deadline)
        end
      end

      module Handshake
        CHALLENGE_LEN = 32
        HMAC_LEN = 32

        class Error < StandardError; end

        module Server
          include TimedIO

          private

          def handshake(socket, secret, timeout = IPC::HANDSHAKE_TIMEOUT)
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

            server_challenge = SecureRandom.bytes(CHALLENGE_LEN)

            write_with_deadline(socket, server_challenge, deadline)

            buffer = read_with_deadline(socket, HMAC_LEN + CHALLENGE_LEN, deadline)

            client_hmac = buffer.byteslice(0, HMAC_LEN)
            client_challenge = buffer.byteslice(HMAC_LEN, CHALLENGE_LEN)

            expected = OpenSSL::HMAC.digest("SHA256", secret, "CLIENT-AUTH" + server_challenge)

            unless OpenSSL.fixed_length_secure_compare(client_hmac, expected)
              socket.close
              raise Error, "client authentication failed"
            end

            server_hmac = OpenSSL::HMAC.digest("SHA256", secret, "SERVER-AUTH" + client_challenge)

            write_with_deadline(socket, server_hmac, deadline)
          rescue Errno::ETIMEDOUT
            socket.close
            raise Error, "handshake timed out"
          rescue EOFError, Errno::ECONNRESET, Errno::EPIPE
            socket.close
            raise Error, "connection closed"
          end
        end

        module Client
          include TimedIO

          private

          def handshake(socket, secret, timeout = IPC::HANDSHAKE_TIMEOUT)
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

            server_challenge = read_with_deadline(socket, CHALLENGE_LEN, deadline)

            client_hmac = OpenSSL::HMAC.digest("SHA256", secret, "CLIENT-AUTH" + server_challenge)
            client_challenge = SecureRandom.bytes(CHALLENGE_LEN)

            write_with_deadline(socket, client_hmac + client_challenge, deadline)

            server_hmac = read_with_deadline(socket, HMAC_LEN, deadline)

            expected = OpenSSL::HMAC.digest("SHA256", secret, "SERVER-AUTH" + client_challenge)

            unless OpenSSL.fixed_length_secure_compare(server_hmac, expected)
              socket.close
              raise Error, "server authentication failed"
            end
          rescue Errno::ETIMEDOUT
            socket.close
            raise Error, "handshake timed out"
          rescue EOFError, Errno::ECONNRESET, Errno::EPIPE
            socket.close
            raise Error, "connection closed"
          end
        end
      end

      class Server
        include Handshake::Server

        attr_reader :host
        attr_reader :port

        def self.start(
          secret,
          host = "127.0.0.1",
          port = 0,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT,
          &block
        )
          server = new(secret, host, port, handshake_timeout: handshake_timeout)
          server.start(&block)
          server
        end

        def initialize(
          secret,
          host = "127.0.0.1",
          port = 0,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT
        )
          @secret = secret
          @handshake_timeout = handshake_timeout

          @running = Concurrent::AtomicBoolean.new(false)

          @server = TCPServer.new(host, port)
          @host = @server.addr[3]
          @port = @server.addr[1]

          @sockets = Concurrent::Array.new
        end

        def accept(&block)
          socket = @server.accept

          @sockets << socket

          Thread.new do
            begin
              handshake(socket, @secret, @handshake_timeout)
            rescue Handshake::Error
              # rejected connection
            else
              # accepted connection
              block.call(socket)
            end
          ensure
            @sockets.delete(socket)

            socket.close
          end
        end

        def close
          @server.close
        end

        def start(&block)
          raise ArgumentError, "block required" unless block

          return false unless @running.make_true

          Thread.new do
            loop do
              accept do |socket|
                # accepted connection
                block.call(socket)
              end
            end
          rescue IOError
            # server stopped
          ensure
            @running.make_false

            close
          end

          true
        end

        def stop(&block)
          return false unless @running.make_false

          block&.call

          close

          @sockets.each do |socket|
            # shutdown(SHUT_RDWR) wakes every thread in every process blocked in
            # read or write (or select) on the socket.
            socket.shutdown(Socket::SHUT_RDWR)
          rescue IOError
            # already closed
          end

          true
        end
      end

      class Client
        include Handshake::Client

        attr_reader :socket

        def self.start(
          secret,
          host = "127.0.0.1",
          port = 0,
          connect_timeout: IPC::CONNECT_TIMEOUT,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT,
          reconnect: false,
          reconnect_delay: IPC::RECONNECT_DELAY,
          &block
        )
          client = new(
            secret,
            host,
            port,
            connect_timeout: connect_timeout,
            handshake_timeout: handshake_timeout,
            reconnect: reconnect,
            reconnect_delay: reconnect_delay
          )
          client.start(&block)
          client
        end

        def initialize(
          secret,
          host = "127.0.0.1",
          port = 0,
          connect_timeout: IPC::CONNECT_TIMEOUT,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT,
          reconnect: false,
          reconnect_delay: IPC::RECONNECT_DELAY
        )
          @secret = secret
          @host = host
          @port = port
          @connect_timeout = connect_timeout
          @handshake_timeout = handshake_timeout
          @reconnect = reconnect
          @reconnect_delay = reconnect_delay

          @running = Concurrent::AtomicBoolean.new(false)

          connect
        end

        def close
          @socket.close
        end

        def start(&block)
          raise ArgumentError, "block required" unless block

          return false unless @running.make_true

          Thread.new do
            loop do
              block.call(@socket)

              break
            rescue
              break unless @reconnect && reconnect
            end
          ensure
            @running.make_false
            close
          end

          true
        end

        def stop(&block)
          return false unless @running.make_false

          block&.call

          close

          true
        end

        private

        def connect
          @socket = connect_with_timeout(@host, @port, @connect_timeout)

          handshake(@socket, @secret, @handshake_timeout)
        end

        def reconnect
          close

          while @running.true?
            begin
              connect

              return true
            rescue
              sleep @reconnect_delay
            end
          end

          false
        end
      end
    end
  end
end
