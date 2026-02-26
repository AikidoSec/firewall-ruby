# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    class IPListChecker
      def initialize(app, zen: Aikido::Zen, config: zen.config, settings: zen.runtime_settings)
        @app = app
        @zen = zen
        @config = config
        @settings = settings
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        client_ip = request.client_ip

        return @app.call(env) if bypassed_ip?(client_ip)

        if !@settings.allowed_ip?(client_ip)
          return @config.blocked_responder.call(request, :ip_allowed_list)
        end

        monitored_ip_list_keys = @settings.monitored_ip_list_keys(client_ip)
        @zen.track_ip_list(monitored_ip_list_keys)

        blocked_ip_lists = @settings.blocked_ip_lists.filter { |ip_list| ip_list.include?(client_ip) }

        if !blocked_ip_lists.empty?
          @zen.track_ip_list(blocked_ip_lists.map(&:key))

          return @config.blocked_responder.call(
            request,
            :ip_blocked_list,
            blocked_ip_lists.first.description
          )
        end

        @app.call(env)
      end

      def bypassed_ip?(client_ip)
        @settings.bypassed_ips.include?(client_ip)
      end
    end
  end
end
