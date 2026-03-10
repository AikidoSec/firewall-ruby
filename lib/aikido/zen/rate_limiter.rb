# frozen_string_literal: true

require_relative "synchronizable"
require_relative "middleware/rack_throttler"

module Aikido::Zen
  # Keeps track of all requests in this process, broken up by Route and further
  # discriminated by client. Provides a single method that checks if a certain
  # Request needs to be throttled or not.
  class RateLimiter
    prepend Synchronizable

    def initialize(
      config: Aikido::Zen.config,
      settings: Aikido::Zen.runtime_settings
    )
      @config = config
      @settings = settings
      @buckets = {}
    end

    # Calculate based on the configuration whether a request will be
    # rate-limited or not.
    #
    # @param request [Aikido::Zen::Request]
    # @return [Aikido::Zen::RateLimiter::Result, nil]
    def calculate_rate_limits(request)
      route, settings = @settings.endpoints.match(request.route)

      rate_limiting_settings = settings&.rate_limiting

      return nil unless rate_limiting_settings&.enabled?

      bucket = synchronize do
        bucket = @buckets[route]

        if bucket.nil? || bucket.settings_changed?(rate_limiting_settings)
          bucket = Bucket.new(
            ttl: rate_limiting_settings.period,
            max_size: rate_limiting_settings.max_requests,
            settings: rate_limiting_settings
          )

          @buckets[route] = bucket
        end

        bucket
      end

      key = @config.rate_limiting_discriminator.call(request)
      bucket.increment(key)
    end
  end
end

require_relative "rate_limiter/bucket"
require_relative "rate_limiter/breaker"
