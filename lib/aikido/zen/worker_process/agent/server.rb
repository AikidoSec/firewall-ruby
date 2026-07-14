# frozen_string_literal: true

module Aikido::Zen::WorkerProcess
  module Agent
    class Server
      def initialize(config: Aikido::Zen.config)
        @config = config

        @rpc_server = Aikido::Zen::RPC::Server.new(Aikido::Zen.secret)

        @rpc_server.handle("ping") do |respond|
          respond.call(nil)
        end

        @rpc_server.handle("updated_settings") do |respond|
          respond.call(updated_settings)
        end

        @rpc_server.handle("send_collector_events") do |respond, events_data|
          respond.call(nil)
          send_collector_events(events_data)
        end

        @rpc_server.handle("calculate_rate_limits") do |respond, route_data, ip, actor_data|
          result = calculate_rate_limits(route_data, ip, actor_data)
          respond.call(result&.as_json)
        end
      end

      def host
        @rpc_server.host
      end

      def port
        @rpc_server.port
      end

      def started?
        !!@started_at
      end

      def close
        @rpc_server.close
      end

      def start
        @config.logger.info("Starting RPC Server...")

        @rpc_server.start

        @started_at = Time.now.utc
      end

      def stop
        @config.logger.info("Stopping RPC Server...")

        @rpc_server.stop

        @started_at = nil
      end

      # @api private
      #
      # Visible for testing.
      RequestKind = Struct.new(:route, :schema, :client_ip, :actor)

      def updated_settings
        {
          "config" => Aikido::Zen.api_cache.runtime_config,
          "firewall_lists" => Aikido::Zen.api_cache.runtime_firewall_lists
        }
      end

      def send_collector_events(events_data)
        events_data.each do |event_data|
          event = Aikido::Zen::Collector::Event.from_json(event_data)
          Aikido::Zen.collector.add_event(event)
        end
      end

      def calculate_rate_limits(route_data, ip, actor_data)
        actor = Aikido::Zen::Actor.from_json(actor_data) if actor_data
        route = Aikido::Zen::Route.from_json(route_data)
        Aikido::Zen.rate_limiter.calculate_rate_limits(RequestKind.new(route, nil, ip, actor))
      end
    end
  end
end
