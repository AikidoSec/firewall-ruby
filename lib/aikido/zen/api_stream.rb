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
      read_timeout: 70
    )
      @config = config
      @min_backoff = min_backoff
      @max_backoff = max_backoff
      @backoff_reset = backoff_reset
      @open_timeout = open_timeout
      @read_timeout = read_timeout

      @started_at = nil
      @stop = Concurrent::AtomicBoolean.new
      @executor = Concurrent::SingleThreadExecutor.new

      @host = @config.realtime_endpoint.host
      @port = @config.realtime_endpoint.port
      @use_ssl = @config.realtime_endpoint.scheme == "https"
      @path = "/api/runtime/stream"
      @token = @config.api_token

      @handlers = []
    end

    def started?
      !!@started_at
    end

    def start!
      return false if started?

      @executor.post do
        backoff = @min_backoff

        loop do
          time_before = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)

          begin
            work
          rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED
            @config.logger.debug("Error in API stream: #{err.class}: #{err.message}")
          rescue => err
            @config.logger.error("Error in API stream: #{err.class}: #{err.message}")
          end

          break if @stop.true?

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

      @started_at = Time.now.utc

      true
    end

    def stop!
      return false unless started?

      @stop.make_true

      @started_at = nil

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
      http.read_timeout = @read_timeout
      http.max_retries = 0

      request = Net::HTTP::Get.new(@path)
      request["Authorization"] = @token
      request["Accept"] = "text/event-stream"
      request["Cache-Control"] = "no-cache"

      @config.logger.debug("API stream connecting")
      http.start
      @config.logger.debug("API stream connected")

      begin
        http.request(request) do |response|
          case response.code
          when "200"
            # empty
          when "401", "403"
            stop!
            return nil
          else
            return nil
          end

          buffer = +""

          response.read_body do |chunk|
            return nil if @stop.true?

            @config.logger.debug("API stream received chunk:\n#{chunk.strip}")

            buffer << chunk

            while (index = buffer.index("\n\n"))
              event_str = buffer.slice!(0..index + 1)
              buffer = buffer.lstrip

              event = {}
              event_str.each_line do |line|
                case line
                when /^event:\s*(.+)/
                  event[:type] = $1
                when /^data:\s*(.+)/
                  event[:data] = begin
                    JSON.parse($1)
                  rescue JSON::ParserError
                    $1
                  end
                end
              end

              @handlers.each do |handler|
                handler.call(event)
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
