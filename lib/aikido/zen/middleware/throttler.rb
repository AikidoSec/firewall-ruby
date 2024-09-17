# frozen_string_literal: true

require_relative "../context"

module Aikido::Zen
  module Middleware
    # Middleware that rejects requests from clients that are making too many
    # requests to a given endpoint, based in the runtime configuration in the
    # Aikido dashboard.
    class Throttler
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
        request = request_from(env)

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

      def request_from(env)
        if (current_context = Aikido::Zen.current_context)
          current_context.request
        else
          Context.from_rack_env(env).request
        end
      end
    end
  end
end
