# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    class IPListChecker
      def initialize(app, zen: Aikido::Zen, config: zen.config, settings: zen.runtime_settings, firewall: zen.firewall)
        @app = app
        @zen = zen
        @config = config
        @settings = settings
        @firewall = firewall
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)

        client_ip = request.client_ip

        return @app.call(env) if bypassed_ip?(client_ip)

        if !@firewall.allowed_ip?(client_ip)
          return @config.blocked_responder.call(request, :ip_allowed_list)
        end

        monitored_ip_list_keys = @firewall.monitored_ip_list_keys(client_ip)
        @zen.track_ip_list(monitored_ip_list_keys)

        matching_blocked_lists = @firewall.matching_blocked_lists(client_ip)

        if !matching_blocked_lists.empty?
          @zen.track_ip_list(matching_blocked_lists.map(&:key))

          return @config.blocked_responder.call(
            request,
            :ip_blocked_list,
            matching_blocked_lists.first.description
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
