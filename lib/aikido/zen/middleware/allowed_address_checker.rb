# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    # Middleware that rejects requests from IPs blocked in the Aikido dashboard.
    class AllowedAddressChecker
      def initialize(app, config: Aikido::Zen.config, settings: Aikido::Zen.runtime_settings)
        @app = app
        @config = config
        @settings = settings
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        allowed_ips = @settings.endpoints[request.route].allowed_ips

        if allowed_ips.empty? || allowed_ips.include?(request.ip)
          @app.call(env)
        else
          @config.blocked_responder.call(request, :ip)
        end
      end
    end
  end
end
