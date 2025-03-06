# frozen_string_literal: true

require_relative "../context"

module Aikido::Zen
  module Middleware
    # Rack middleware that rejects requests from clients that are making too many
    # requests to a given endpoint, based in the runtime configuration in the
    # Aikido dashboard.
    class RackThrottler
      def initialize(
        app,
        config: Aikido::Zen.config,
        settings: Aikido::Zen.runtime_settings,
        rate_limiter: Aikido::Zen::RateLimiter.new
      )
        @app = app
        @config = config
        @settings = settings
        @rate_limiter = rate_limiter
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        Aikido::Zen.middleware_installed!

        if should_throttle?(request)
          @config.rate_limited_responder.call(request)
        else
          @app.call(env)
        end
      end

      private

      def should_throttle?(request)
        return false if @settings.skip_protection_for_ips.include?(request.ip)

        @rate_limiter.throttle?(request)
      end
    end
  end
end
