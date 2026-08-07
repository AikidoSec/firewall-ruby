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
        # No context means ContextSetter never ran, so there is nothing to mark.
        if (context = @zen.current_context)
          context.protection_disabled = protection_disabled?(context.request)
        end

        @app.call(env)
      end

      private def protection_disabled?(request)
        return true if @settings.bypassed_ips.include?(request.client_ip)

        !@settings.endpoints.matched_settings(request.route).all?(&:protected?)
      end
    end
  end
end
