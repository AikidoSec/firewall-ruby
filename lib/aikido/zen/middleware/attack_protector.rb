# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    class AttackProtector
      def initialize(app, zen: Aikido::Zen, settings: zen.runtime_settings)
        @app = app
        @zen = zen
        @settings = settings
      end

      def call(env)
        context = @zen.current_context
        request = context.request

        context.protection_disabled = protection_disabled?(request)

        @app.call(env)
      end

      private def protection_disabled?(request)
        #debugger if request.client_ip == "::ffff:23.45.67.89"
        return true if @settings.bypassed_ips.include?(request.client_ip)

        !@settings.endpoints.match(request.route).all?(&:protected?)
      end
    end
  end
end
