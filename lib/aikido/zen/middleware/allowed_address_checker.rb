# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    # Middleware that only allows allowed IPs when allowed IPs are configured for
    # any matching route in the Aikido dashboard.
    class AllowedAddressChecker
      def initialize(app, zen: Aikido::Zen, config: zen.config, settings: zen.runtime_settings)
        @app = app
        @zen = zen
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
        return true if @zen.request_bypassed?

        matches = @settings.endpoints.matched_settings(request.route)

        matches.all? { |settings| settings.allowed_ips.empty? } ||
          matches.any? { |settings| settings.allowed_ips.include?(request.ip) }
      end
    end
  end
end
