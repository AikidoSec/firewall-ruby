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
        ipc_client: Aikido::Zen.ipc_client
      )
        @app = app
        @config = config
        @settings = settings
        @ipc_client = ipc_client
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        if should_throttle?(request)
          @config.rate_limited_responder.call(request)
        else
          @app.call(env)
        end
      end

      private

      def should_throttle?(request)
        return false unless @settings.endpoints[request.route].rate_limiting.enabled?
        return false if @settings.skip_protection_for_ips.include?(request.ip)

        result = @ipc_client.calculate_rate_limits(request)

        return false unless result

        request.env["aikido.rate_limiting"] = result
        request.env["aikido.rate_limiting"].throttled?
      end
    end
  end
end
