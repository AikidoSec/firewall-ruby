# frozen_string_literal: true

module Aikido::Zen
  # Simple data object that holds the configuration for rate limiting a given
  # endpoint.
  class RuntimeSettings::RateLimitSettings
    # Initialize the settings from an API response.
    #
    # @param data [Hash] the deserialized JSON data.
    # @option data [Boolean] "enabled"
    # @option data [Integer] "maxRequests"
    # @option data [Integer] "windowSizeInMS"
    #
    # @return [Aikido::Zen::RateLimitSettings]
    def self.from_json(data)
      new(
        enabled: !!data["enabled"],
        max_requests: Integer(data["maxRequests"]),
        period: Integer(data["windowSizeInMS"]) / 1000
      )
    end

    # Initializes a disabled object that we can use as a default value for
    # endpoints that have not configured rate limiting.
    #
    # @return [Aikido::Zen::RuntimeSettings::RateLimitSettings]
    def self.disabled
      new(enabled: false)
    end

    # @return [Integer] the fixed window to bucket requests in, in seconds.
    attr_reader :period

    # @return [Integer]
    attr_reader :max_requests

    def initialize(enabled: false, max_requests: 1000, period: 60)
      @enabled = enabled
      @period = period
      @max_requests = max_requests
    end

    def enabled?
      @enabled
    end
  end
end
