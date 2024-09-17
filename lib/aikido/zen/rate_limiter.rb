# frozen_string_literal: true

require_relative "synchronizable"
require_relative "middleware/throttler"

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
      @buckets = Hash.new { |store, route|
        synchronize {
          settings = settings_for(route)
          store[route] = Bucket.new(ttl: settings.period, max_size: settings.max_requests)
        }
      }
    end

    # Checks whether the request requires rate limiting. As a side effect, this
    # will annotate the request with the "aikido.rate_limiting" ENV key, holding
    # the result of the check, and including useful stats in case you want to
    # return RateLimit headers..
    #
    # @param request [Aikido::Zen::Request]
    # @return [Boolean]
    #
    # @see Aikido::Zen::RateLimiter::Result
    def throttle?(request)
      settings = settings_for(request.route)
      return false unless settings.enabled?

      bucket = @buckets[request.route]
      key = @config.rate_limiting_discriminator.call(request)
      request.env["aikido.rate_limiting"] = bucket.increment(key)
      request.env["aikido.rate_limiting"].throttled?
    end

    private

    def settings_for(route)
      @settings.endpoints[route].rate_limiting
    end
  end
end

require_relative "rate_limiter/bucket"
require_relative "rate_limiter/breaker"
