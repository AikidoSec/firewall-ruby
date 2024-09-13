# frozen_string_literal: true

require_relative "../context"

module Aikido::Zen
  module Middleware
    # Middleware that rejects requests from IPs blocked in the Aikido dashboard.
    class CheckAllowedAddresses
      def initialize(app, config: Aikido::Zen.config, settings: Aikido::Zen.runtime_settings)
        @app = app
        @config = config
        @settings = settings
      end

      def call(env)
        request = request_from(env)

        allowed_ips = @settings.endpoints[request.route].allowed_ips

        if allowed_ips.empty? || allowed_ips.include?(request.ip)
          @app.call(env)
        else
          @config.blocked_ip_responder.call(request)
        end
      end

      private

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
