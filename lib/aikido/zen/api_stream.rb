# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Aikido::Zen
  class APIStream
    def initialize(
      config: Aikido::Zen.config,
      min_backoff: 5,
      max_backoff: 60,
      backoff_reset: 30,
      open_timeout: 5,
      write_timeout: open_timeout,
      read_timeout: 70
    )
      @config = config
      @min_backoff = min_backoff
      @max_backoff = max_backoff
      @backoff_reset = backoff_reset
      @open_timeout = open_timeout
      @write_timeout = write_timeout
      @read_timeout = read_timeout

      @running = Concurrent::AtomicBoolean.new
      @thread = nil

      endpoint = @config.realtime_settings_updates_endpoint

      @host = endpoint.host
      @port = endpoint.port
      @use_ssl = endpoint.scheme == "https"
      @token = @config.api_token

      @handlers = Concurrent::Array.new
    end

    # @return [Boolean] whether we could connect to the realtime endpoint
    def can_connect?
      http = Net::HTTP.new(@host, @port)
      http.use_ssl = @use_ssl
      http.open_timeout = 5
      http.write_timeout = 5
      http.read_timeout = 5
      http.max_retries = 0

      request = Net::HTTP::Get.new("/config")
      request["Authorization"] = @token

      begin
        http.request(request)

        return true
      rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::OpenSSLError => err
        @config.logger.debug("Error probing realtime endpoint: #{err.class}: #{err.message}")
      rescue => err
        @config.logger.error("Error probing realtime endpoint: #{err.class}: #{err.message}")
      end

      false
    end

    def running?
      @running.true?
    end
    alias_method :started?, :running?

    def start!
      return false unless @running.make_true

      @thread = Thread.new do
        backoff = @min_backoff

        while running?
          time_before = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)

          begin
            work
          rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::OpenSSLError => err
            @config.logger.debug("Error in API stream: #{err.class}: #{err.message}")
          rescue => err
            @config.logger.error("Error in API stream: #{err.class}: #{err.message}")
          end

          break unless running?

          time_after = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)

          backoff = if time_after - time_before > @backoff_reset
            @min_backoff
          else
            [backoff * 2, @max_backoff].min
          end

          jitter = rand * backoff / 2

          @config.logger.debug("API stream reconnecting in %d seconds" % (backoff + jitter).ceil)

          sleep(backoff + jitter)
        end
      end

      true
    end

    def stop!
      return false unless @running.make_false

      @thread.join(@read_timeout)

      true
    end

    def handle(type, &block)
      raise ArgumentError, "block required" unless block

      @handlers << proc do |event|
        block.call(event) if type === event[:type]
      end
    end

    private def work
      http = Net::HTTP.new(@host, @port)
      http.use_ssl = @use_ssl
      http.open_timeout = @open_timeout
      http.write_timeout = @write_timeout
      http.read_timeout = @read_timeout
      http.max_retries = 0

      request = Net::HTTP::Get.new("/api/runtime/stream")
      request["Authorization"] = @token
      request["Accept"] = "text/event-stream"
      request["Cache-Control"] = "no-cache"

      @config.logger.debug("API stream connecting")
      http.start
      @config.logger.debug("API stream connected")

      begin
        http.request(request) do |response|
          case response.code.to_i
          when 200
            # empty
          when 401, 403
            @running.make_false
            return nil
          else
            return nil
          end

          buffer = +""

          response.read_body do |chunk|
            return nil unless running?

            @config.logger.debug("API stream received chunk of #{chunk.bytesize} bytes")

            buffer << chunk

            while (index = buffer.index("\n\n"))
              event_str = buffer.slice!(0..index + 1)
              buffer = buffer.lstrip

              event = {}

              begin
                event_str.each_line do |line|
                  case line
                  when /^event:\s*(.+)/
                    event[:type] = $1.strip
                  when /^data:\s*(.+)/
                    event[:data] = JSON.parse($1.strip)
                  end
                end
              rescue => err
                @config.logger.error("Error in API stream: #{err.class}: #{err.message}")
                next
              end

              @handlers.each do |handler|
                handler.call(event)
              rescue => err
                @config.logger.error("Error in API stream: #{err.class}: #{err.message}")
              end
            end
          end
        end
      ensure
        @config.logger.debug("API stream disconnecting")
        http.finish
        @config.logger.debug("API stream disconnected")
      end
    end
  end
end
