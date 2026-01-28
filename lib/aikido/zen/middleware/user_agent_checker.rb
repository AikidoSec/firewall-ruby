# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    class UserAgentChecker
      def initialize(app, zen: Aikido::Zen, config: zen.config, settings: zen.runtime_settings)
        @app = app
        @zen = zen
        @config = config
        @settings = settings
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        return @app.call(env) if bypassed?(request)

        user_agent = request.user_agent

        if @settings.blocked_user_agent?(user_agent)
          user_agent_keys = @settings.user_agent_keys(user_agent)
          @zen.track_user_agent(user_agent_keys)

          return @config.blocked_responder.call(request, :user_agent)
        end

        if @settings.monitored_user_agent?(user_agent)
          user_agent_keys = @settings.user_agent_keys(user_agent)
          @zen.track_user_agent(user_agent_keys)
        end

        @app.call(env)
      end

      def bypassed?(request)
        # Bypass for allowed IPs
        @settings.allowed_ips.include?(request.ip)
      end
    end
  end
end
