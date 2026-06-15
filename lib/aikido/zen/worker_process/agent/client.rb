# frozen_string_literal: true

require_relative "../../background_worker"

module Aikido::Zen::WorkerProcess
  module Agent
    class Client
      # The keepalive interval must be less than the RPC server read timeout.
      KEEPALIVE_INTERVAL = 4

      def initialize(
        host,
        port,
        secret: Aikido::Zen.secret,
        config: Aikido::Zen.config,
        worker: Aikido::Zen::Worker.new(config: config),
        polling_interval: config.worker_process_polling_interval,
        heartbeat_interval: config.worker_process_heartbeat_interval,
        collector: Aikido::Zen.collector
      )
        @config = config
        @worker = worker
        @polling_interval = polling_interval
        @heartbeat_interval = heartbeat_interval
        @collector = collector

        @rpc_client = Aikido::Zen::RPC::Client.new(secret, host, port)
      end

      def close
        @rpc_client.close
      end

      def start
        @rpc_client.start

        begin
          update_settings(updated_settings)
        rescue => err
          @config.logger.error("Forked worker process #{Process.pid}: failed to get initial settings from parent: #{err.message}")
        end

        schedule_tasks
      end

      def stop
        @worker.shutdown
        @rpc_client.stop
      end

      def send_collector_events
        events_data = @collector.flush_events.map(&:as_json)
        @rpc_client.invoke("send_collector_events", events_data)
      rescue => err
        @config.logger.error("Forked worker process #{Process.pid}: failed to send collector events to parent: #{err.message}")
      end

      def calculate_rate_limits(request)
        result = @rpc_client.invoke(
          "calculate_rate_limits",
          request.route.as_json, request.client_ip, request.actor&.as_json,
          timeout: Aikido::Zen::IPC::READ_TIMEOUT
        )

        Aikido::Zen::RateLimiter::Result.from_json(result) if result
      rescue => err
        @config.logger.error("Forked worker process #{Process.pid}: failed to get rate limits from parent: #{err.message}")
        nil
      end

      private

      def updated_settings
        @rpc_client.invoke("updated_settings", timeout: Aikido::Zen::IPC::READ_TIMEOUT)
      end

      def update_settings(settings)
        return unless settings

        if settings["config"]
          Aikido::Zen.runtime_settings.update_from_runtime_config_json(settings["config"])
        end

        if settings["firewall_lists"]
          Aikido::Zen.runtime_settings.update_from_runtime_firewall_lists_json(settings["firewall_lists"])
        end
      end

      def schedule_tasks
        @worker.every(KEEPALIVE_INTERVAL, run_now: false) { keepalive }

        @worker.every(@polling_interval, run_now: false) do
          update_settings(updated_settings)

          @config.logger.debug("Forked worker process #{Process.pid}: updated runtime settings from parent")
        rescue => err
          @config.logger.error("Forked worker process #{Process.pid}: failed to get settings from parent: #{err.message}")
        end

        @worker.every(@heartbeat_interval, run_now: false) { send_collector_events }
      end

      def keepalive
        @rpc_client.invoke("ping")
      rescue => err
        @config.logger.error("Forked worker process #{Process.pid}: keepalive failed: #{err.message}")
      end
    end
  end
end
