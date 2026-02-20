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

        #debugger

        if !allowed_ip?(client_ip) && blocked_ip?(client_ip)
          return @config.blocked_responder.call(request, :ip_list, reason: "geo restrictions")
        end

        @app.call(env)
      end

      def bypassed_ip?(client_ip)
        @settings.bypassed_ips.include?(client_ip)
      end

      def allowed_ip?(client_ip)
        @settings.allowed_ip_lists.any? { |ip_list| ip_list.include?(client_ip) }
      end

      def blocked_ip?(client_ip)
        @settings.blocked_ip_lists.any? { |ip_list| ip_list.include?(client_ip) }
      end
    end
  end
end
