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
      @buckets = Hash.new { |store, route|
        synchronize {
          settings = settings_for(route)
          store[route] = Bucket.new(ttl: settings.period, max_size: settings.max_requests)
        }
      }
    end

    # Calculate based on the configuration whether a request will be
    # rate-limited or not.
    #
    # @param request [Aikido::Zen::Request]
    # @return [Aikido::Zen::RateLimiter::Result, nil]
    def calculate_rate_limits(request)
      route, enabled = resolve_route_enabled(request)
      return nil unless enabled

      bucket = @buckets[route]
      key = @config.rate_limiting_discriminator.call(request)
      bucket.increment(key)
    end

    private

    def resolve_route_enabled(request)
      @settings.endpoints.match(request.route) do |route, settings|
        [route, settings.rate_limiting.enabled?]
      end
    end

    def settings_for(route)
      @settings.endpoints[route].rate_limiting
    end
  end
end

require_relative "rate_limiter/bucket"
require_relative "rate_limiter/breaker"
