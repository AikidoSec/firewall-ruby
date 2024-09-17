# frozen_string_literal: true

require "net/http"
require_relative "rate_limiter"

module Aikido::Zen
  # Implements all communication with the Aikido servers.
  class APIClient
    def initialize(
      config: Aikido::Zen.config,
      rate_limiter: Aikido::Zen::RateLimiter::Breaker.new,
      system_info: Aikido::Zen.system_info
    )
      @config = config
      @system_info = system_info
      @rate_limiter = rate_limiter
    end

    # @return [Boolean] whether we have a configured token.
    def can_make_requests?
      @config.api_token.to_s.size > 0
    end

    # Checks with the Aikido Runtime API the timestamp of the last settings
    # update, and compares against the given value.
    #
    # @param last_updated_at [Time]
    #
    # @return [Boolean]
    # @raise (see #request)
    def should_fetch_settings?(last_updated_at = Aikido::Zen.runtime_settings.updated_at)
      @config.logger.debug("Polling for new runtime settings to fetch")

      return false unless can_make_requests?
      return true if last_updated_at.nil?

      response = request(
        Net::HTTP::Get.new("/config", default_headers),
        base_url: @config.runtime_api_base_url
      )

      new_updated_at = Time.at(response["configUpdatedAt"].to_i / 1000)
      new_updated_at > last_updated_at
    end

    # Fetches the runtime settings from the server. In case of a timeout or
    # other low-lever error, the request will be automatically retried up to two
    # times, after which it will raise an error.
    #
    # @return [Hash] decoded JSON response from the server with the runtime
    #   settings.
    # @raise (see #request)
    def fetch_settings
      @config.logger.debug("Fetching new runtime settings")

      request(Net::HTTP::Get.new("/api/runtime/config", default_headers))
    end

    # @overload report(event)
    #   Reports an event to the server.
    #
    #   @param event [Aikido::Zen::Event]
    #   @return [void]
    #   @raise (see #request)
    #
    # @overload report(settings_updating_event)
    #   Reports an event that responds with updated runtime settings, and
    #   requires us to update settings afterwards.
    #
    #   @param settings_updating_event [Aikido::Zen::Events::Started,
    #     Aikido::Zen::Events::Heartbeat]
    #   @return (see #fetch_settings)
    #   @raise (see #request)
    def report(event)
      if @rate_limiter.throttle?(event)
        @config.logger.error("Not reporting #{event.type.upcase} event due to rate limiting")
        return
      end

      @config.logger.debug("Reporting #{event.type.upcase} event")

      req = Net::HTTP::Post.new("/api/runtime/events", default_headers)
      req.content_type = "application/json"
      req.body = @config.json_encoder.call(event.as_json)

      request(req)
    rescue Aikido::Zen::RateLimitedError
      @rate_limiter.open!
      raise
    end

    # Perform an HTTP request against one of our API endpoints, and process the
    # response.
    #
    # @param request [Net::HTTPRequest]
    # @param base_url [URI] which API to use. Defaults to +Config#api_base_url+.
    #
    # @return [Object] the result of decoding the JSON response from the server.
    #
    # @raise [Aikido::Zen::APIError] in case of a 4XX or 5XX response.
    # @raise [Aikido::Zen::NetworkError] if an error occurs trying to make the
    #   request.
    private def request(request, base_url: @config.api_base_url)
      Net::HTTP.start(base_url.host, base_url.port, http_settings) do |http|
        response = http.request(request)

        case response
        when Net::HTTPSuccess
          @config.json_decoder.call(response.body)
        when Net::HTTPTooManyRequests
          raise RateLimitedError.new(request, response)
        else
          raise APIError.new(request, response)
        end
      end
    rescue Timeout::Error, IOError, SystemCallError, OpenSSL::OpenSSLError => err
      raise NetworkError.new(request, err)
    end

    private def http_settings
      @http_settings ||= {use_ssl: true, max_retries: 2}.merge(@config.api_timeouts)
    end

    private def default_headers
      @default_headers ||= {
        "Authorization" => @config.api_token,
        "Accept" => "application/json",
        "User-Agent" => "#{@system_info.library_name} v#{@system_info.library_version}"
      }
    end
  end
end
