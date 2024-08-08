# frozen_string_literal: true

require "net/http"

module Aikido::Agent
  # Implements all communication with the Aikido servers.
  class APIClient
    def initialize(config = Aikido::Agent.config)
      @config = config
    end

    # @return [Boolean] whether we have a configured token.
    def can_make_requests?
      @config.api_token.to_s.size > 0
    end

    # Fetches the Firewall settings from the server. In case of a timeout or
    # other low-lever error, the request will be automatically retried up to two
    # times, after which it will raise an error.
    #
    # @return [Hash] decoded JSON response from the server.
    # @raise [Aikido::Agent::APIError] in case of a 4XX or 5XX response.
    # @raise [Aikido::Agent::NetworkError] if an error occurs trying to make the
    #   request.
    def fetch_settings
      request(Net::HTTP::Get.new("/api/runtime/config", default_headers))
    end

    private def request(request, base_url: @config.api_base_url)
      Net::HTTP.start(base_url.host, base_url.port, http_settings) do |http|
        response = http.request(request)

        case response
        when Net::HTTPSuccess
          @config.json_decoder.call(response.body)
        else
          raise APIError.new(request, response)
        end
      end
    rescue Timeout::Error, IOError, SystemCallError, OpenSSL::OpenSSLError => err
      raise NetworkError, err.message
    end

    private def http_settings
      @http_settings ||= {use_ssl: true, max_retries: 2}.merge(@config.api_timeouts)
    end

    private def default_headers
      @default_headers ||= {
        "Authorization" => @config.api_token,
        "Accept" => "application/json",
        "User-Agent" => "firewall-ruby v#{VERSION}"
      }
    end
  end
end
