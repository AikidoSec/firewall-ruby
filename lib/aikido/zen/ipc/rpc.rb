# frozen_string_literal: true

require "json"
require "securerandom"
require "concurrent"

module Aikido
  module Zen
    module RPC
      class NoHandlerError < StandardError; end

      class Server
        include IPC::FramedIO

        def self.start(
          secret,
          host = "127.0.0.1",
          port = 0,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT,
          read_timeout: IPC::READ_TIMEOUT,
          write_timeout: IPC::WRITE_TIMEOUT,
          max_read_size: nil,
          max_write_size: nil,
          logger: Aikido::Zen.config.logger,
          &block
        )
          server = new(
            secret,
            host,
            port,
            handshake_timeout: handshake_timeout,
            read_timeout: read_timeout,
            write_timeout: write_timeout,
            max_read_size: max_read_size,
            max_write_size: max_write_size,
            logger: logger
          )

          block&.call(server)

          server.start
          server
        end

        def initialize(
          secret,
          host = "127.0.0.1",
          port = 0,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT,
          read_timeout: IPC::READ_TIMEOUT,
          write_timeout: IPC::WRITE_TIMEOUT,
          max_read_size: nil,
          max_write_size: nil,
          logger: Aikido::Zen.config.logger
        )
          @read_timeout = read_timeout
          @write_timeout = write_timeout
          @max_read_size = max_read_size
          @max_write_size = max_write_size
          @logger = logger

          @handlers = {}

          @server = IPC::Server.new(
            secret,
            host,
            port,
            handshake_timeout: handshake_timeout
          )
        end

        def host
          @server.host
        end

        def port
          @server.port
        end

        def start
          @server.start do |socket|
            @logger.info("RPC server: client connected")

            handle_messages(socket)
          rescue EOFError, Errno::ECONNRESET, Errno::EPIPE
            # disconnected
          rescue IOError
            # client stopped
          rescue => err
            @logger.error("RPC server error: #{err.class}: #{err.message}")
            @logger.debug(err.backtrace.join("\n"))
          ensure
            @logger.info("RPC server: client disconnected")
          end
        end

        def stop
          @server.stop
        end

        def handle(name, &block)
          @handlers[name] = block
        end

        private

        def handle_messages(socket)
          write_mutex = Mutex.new
          buffer = String.new(encoding: Encoding::BINARY)

          loop do
            message = read_message(socket, buffer)
            next unless valid_message?(message)

            handle_message(message, write_mutex, socket)
          end
        end

        def handle_message(message, write_mutex, socket)
          id, name, args, kwargs = message
          kwargs.transform_keys!(&:to_sym)

          respond_called = false

          respond = proc do |result|
            write_mutex.synchronize do
              next if respond_called

              write_message(socket, [id, result, nil])

              respond_called = true
            end
          end

          handler = @handlers[name]

          raise NoHandlerError, "undefined handler '#{name}'" unless handler

          handler.call(respond, *args, **kwargs)

          respond.call(nil)
        rescue => err
          @logger.error("RPC server error handling '#{name}': #{err.class}: #{err.message}")
          @logger.debug(err.backtrace.join("\n"))

          write_mutex.synchronize do
            next if respond_called

            write_message(socket, [id, nil, err.message])
          end
        end

        def valid_message?(message)
          return false unless message.is_a?(Array)
          return false unless message.length == 4
          return false unless message[0].is_a?(String)
          return false unless message[1].is_a?(String)
          return false unless message[2].is_a?(Array)
          return false unless message[3].is_a?(Hash)

          true
        end

        def read_message(socket, buffer)
          JSON.parse(read_coalesced_frame_with_timeout(socket, buffer, @max_read_size, @read_timeout))
        end

        def write_message(socket, message)
          write_coalesced_frame_with_timeout(socket, JSON.generate(message), @max_write_size, @write_timeout)
        end
      end

      class Client
        include IPC::FramedIO

        def self.start(
          secret,
          host,
          port,
          connect_timeout: IPC::CONNECT_TIMEOUT,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT,
          read_timeout: IPC::READ_TIMEOUT,
          write_timeout: IPC::WRITE_TIMEOUT,
          max_read_size: nil,
          max_write_size: nil,
          logger: Aikido::Zen.config.logger
        )
          client = new(
            secret,
            host,
            port,
            connect_timeout: connect_timeout,
            handshake_timeout: handshake_timeout,
            read_timeout: read_timeout,
            write_timeout: write_timeout,
            max_read_size: max_read_size,
            max_write_size: max_write_size,
            logger: logger
          )
          client.start
          client
        end

        def initialize(
          secret,
          host,
          port,
          connect_timeout: IPC::CONNECT_TIMEOUT,
          handshake_timeout: IPC::HANDSHAKE_TIMEOUT,
          read_timeout: IPC::READ_TIMEOUT,
          write_timeout: IPC::WRITE_TIMEOUT,
          max_read_size: nil,
          max_write_size: nil,
          logger: Aikido::Zen.config.logger
        )
          @read_timeout = read_timeout
          @write_timeout = write_timeout
          @max_read_size = max_read_size
          @max_write_size = max_write_size
          @logger = logger

          @pending = Concurrent::Hash.new
          @write_mutex = Mutex.new

          @client = IPC::Client.new(
            secret,
            host,
            port,
            connect_timeout: connect_timeout,
            handshake_timeout: handshake_timeout
          )
        end

        def close
          @client.close
        end

        def start
          @client.start do |socket|
            @logger.info("RPC client connected")

            handle_messages(socket)
          rescue EOFError, Errno::ECONNRESET, Errno::EPIPE => err
            # disconnected
          rescue IOError => err
            # client stopped
          rescue => err
            @logger.error("RPC client error: #{err.class}: #{err.message}")
            @logger.debug(err.backtrace.join("\n"))
          ensure
            @logger.info("RPC client disconnected")

            @client.stop

            @pending.each_value { |ivar| ivar.fail(err) }
            @pending.clear
          end
        end

        def stop
          @client.stop do
            # shutdown(SHUT_RDWR) wakes every thread in every process blocked in
            # read or write (or select) on the socket.
            @client.socket.shutdown(Socket::SHUT_RDWR)
          rescue IOError
            # already closed
          end
        end

        def invoke(name, *args, timeout: nil, **kwargs)
          id = SecureRandom.uuid

          ivar = Concurrent::IVar.new

          @pending[id] = ivar

          @write_mutex.synchronize { write_message(@client.socket, [id, name, args, kwargs]) }

          ivar.wait!(timeout)

          raise Errno::ETIMEDOUT, "invoke timed out" if ivar.incomplete?

          ivar.value
        ensure
          @pending.delete(id)
        end

        private

        def handle_messages(socket)
          buffer = String.new(encoding: Encoding::BINARY)

          loop do
            message = read_message(socket, buffer)
            next unless valid_message?(message)

            handle_message(message)
          end
        end

        def handle_message(message)
          id, result, error = message

          ivar = @pending.delete(id)
          return unless ivar

          if error
            ivar.fail(RuntimeError.new(error))
          else
            ivar.set(result)
          end
        end

        def valid_message?(message)
          return false unless message.is_a?(Array)
          return false unless message.length == 3
          return false unless message[0].is_a?(String)

          true
        end

        def read_message(socket, buffer)
          JSON.parse(read_coalesced_frame_with_timeout(socket, buffer, @max_read_size, @read_timeout))
        end

        def write_message(socket, message)
          write_coalesced_frame_with_timeout(socket, JSON.generate(message), @max_write_size, @write_timeout)
        end
      end
    end
  end
end
