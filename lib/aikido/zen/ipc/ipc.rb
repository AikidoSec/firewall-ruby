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

        def read_with_deadline(socket, length, deadline)
          buf = String.new(encoding: Encoding::BINARY)

          while buf.bytesize < length
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)

            raise Errno::ETIMEDOUT, "read timed out" unless remaining > 0

            case chunk = socket.read_nonblock(length - buf.bytesize, exception: false)
            # Code coverage is disabled here because this is hard to control.
            # :nocov:
            when :wait_readable
              raise Errno::ETIMEDOUT, "read timed out" unless ::IO.select([socket], nil, nil, remaining)
            # :nocov:
            when nil
              raise EOFError
            else
              buf << chunk
            end
          end

          buf
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

        class FrameTooLargeError < StandardError
          def initialize(size, max_size)
            super("frame too large: #{size} bytes (max: #{max_size})")
          end
        end

        private

        def read_frame_with_deadline(socket, max_size, deadline)
          len = read_with_deadline(socket, 4, deadline).unpack1("N")

          if max_size && len > max_size
            raise FrameTooLargeError.new(len, max_size)
          end

          read_with_deadline(socket, len, deadline)
        end

        def read_frame_with_timeout(socket, max_size, timeout)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

          read_frame_with_deadline(socket, max_size, deadline)
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

            buf = read_with_deadline(socket, HMAC_LEN + CHALLENGE_LEN, deadline)

            client_hmac = buf.byteslice(0, HMAC_LEN)
            client_challenge = buf.byteslice(HMAC_LEN, CHALLENGE_LEN)

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
          &block
        )
          client = new(secret, host, port, connect_timeout: connect_timeout, handshake_timeout: handshake_timeout)
          client.start(&block)
          client
        end

        def initialize(
          secret,
          host = "127.0.0.1",
          port = 0,
          connect_timeout: IPC::CONNECT_TIMEOUT,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT
        )
          @running = Concurrent::AtomicBoolean.new(false)

          @socket = connect_with_timeout(host, port, connect_timeout)
          handshake(@socket, secret, handshake_timeout)
        end

        def close
          @socket.close
        end

        def start(&block)
          raise ArgumentError, "block required" unless block

          return false unless @running.make_true

          Thread.new do
            block.call(@socket)
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
      end
    end
  end
end
