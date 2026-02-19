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
        zen: Aikido::Zen,
        config: Aikido::Zen.config,
        settings: Aikido::Zen.runtime_settings,
        detached_agent: Aikido::Zen.detached_agent
      )
        @zen = zen
        @app = app
        @config = config
        @settings = settings
        @detached_agent = detached_agent
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        if should_throttle?(request)
          @zen.track_rate_limited_request(request)
          @config.rate_limited_responder.call(request)
        else
          @app.call(env)
        end
      end

      private

      def should_throttle?(request)
        return false if @settings.bypassed_ips.include?(request.client_ip)

        return false unless @settings.endpoints[request.route].rate_limiting.enabled?

        result = @detached_agent.calculate_rate_limits(request)

        return false unless result

        request.env["aikido.rate_limiting"] = result
        request.env["aikido.rate_limiting"].throttled?
      end
    end
  end
end
