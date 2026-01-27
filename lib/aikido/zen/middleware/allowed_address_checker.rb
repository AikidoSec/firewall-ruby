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

        if allowed?(request)
          @app.call(env)
        else
          @config.blocked_responder.call(request, :ip)
        end
      end

      private def allowed?(request)
        # Bypass for allowed IPs
        return true if @settings.allowed_ips.include?(request.ip)

        matches = @settings.endpoints.match(request.route)

        matches.all? { |settings| settings.allowed_ips.empty? } ||
          matches.any? { |settings| settings.allowed_ips.include?(request.ip) }
      end
    end
  end
end
