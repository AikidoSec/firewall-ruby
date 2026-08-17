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
        return true if @zen.request_bypassed?

        !@settings.endpoints.matched_settings(request.route).all?(&:protected?)
      end
    end
  end
end
