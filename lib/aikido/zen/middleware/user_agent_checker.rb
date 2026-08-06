# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    class UserAgentChecker
      def initialize(app, zen: Aikido::Zen, config: zen.config, settings: zen.runtime_settings, firewall: zen.firewall)
        @app = app
        @zen = zen
        @config = config
        @settings = settings
        @firewall = firewall
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        return @app.call(env) if bypassed?(request)

        user_agent = request.user_agent

        if @firewall.blocked_user_agent?(user_agent)
          user_agent_keys = @firewall.user_agent_keys(user_agent)
          @zen.track_user_agent(user_agent_keys)

          return @config.blocked_responder.call(request, :user_agent)
        end

        if @firewall.monitored_user_agent?(user_agent)
          user_agent_keys = @firewall.user_agent_keys(user_agent)
          @zen.track_user_agent(user_agent_keys)
        end

        @app.call(env)
      end

      def bypassed?(request)
        @settings.bypassed_ips.include?(request.client_ip)
      end
    end
  end
end
