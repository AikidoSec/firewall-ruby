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
        keepalive_worker: Aikido::Zen::Worker.new(config: config),
        polling_interval: config.worker_process_polling_interval,
        polling_jitter: config.worker_process_polling_jitter,
        heartbeat_interval: config.worker_process_heartbeat_interval,
        collector: Aikido::Zen.collector
      )
        @config = config
        @worker = worker
        @keepalive_worker = keepalive_worker
        @polling_interval = polling_interval
        @polling_jitter = polling_jitter
        @heartbeat_interval = heartbeat_interval
        @collector = collector

        @rpc_client = Aikido::Zen::RPC::Client.new(secret, host, port, reconnect: true)

        @known_config_generation = nil
        @known_firewall_lists_generation = nil
      end

      def close
        @rpc_client.close
      end

      def start
        @rpc_client.start do
          @worker.perform do
            update_settings(updated_settings)
          rescue => err
            @config.logger.error("Forked worker process #{Process.pid}: failed to get settings after connecting to parent: #{err.message}")
          end
        end

        schedule_tasks
      end

      def stop
        @keepalive_worker.shutdown
        @worker.shutdown
        @rpc_client.stop
      end

      def send_collector_events
        events_data = @collector.flush_events.map(&:as_json)
        @rpc_client.invoke("send_collector_events", KEEPALIVE_INTERVAL, events_data)
      rescue => err
        @config.logger.error("Forked worker process #{Process.pid}: failed to send collector events to parent: #{err.message}")
      end

      def calculate_rate_limits(request)
        result = @rpc_client.invoke(
          "calculate_rate_limits", Aikido::Zen::IPC::READ_TIMEOUT,
          request.route.as_json, request.client_ip, request.actor&.as_json
        )

        Aikido::Zen::RateLimiter::Result.from_json(result) if result
      rescue => err
        @config.logger.error("Forked worker process #{Process.pid}: failed to get rate limits from parent: #{err.message}")
        raise
      end

      private

      def updated_settings
        @rpc_client.invoke(
          "updated_settings",
          KEEPALIVE_INTERVAL,
          @known_config_generation,
          @known_firewall_lists_generation
        )
      end

      def update_settings(settings)
        return false unless settings

        updated = false

        if settings["config"]
          Aikido::Zen.runtime_settings.update_from_runtime_config_json(settings["config"])
          @known_config_generation = settings["config_generation"]
          updated = true
        end

        if settings["firewall_lists"]
          Aikido::Zen.runtime_settings.update_from_runtime_firewall_lists_json(settings["firewall_lists"])
          @known_firewall_lists_generation = settings["firewall_lists_generation"]
          updated = true
        end

        updated
      end

      def schedule_tasks
        @keepalive_worker.every(KEEPALIVE_INTERVAL, run_now: false) { keepalive }

        # Delay start polling to reduce the chance of workers polling in lockstep.
        @worker.delay(polling_start_delay) { start_polling }

        @worker.every(@heartbeat_interval, run_now: false) { send_collector_events }
      end

      def start_polling
        @worker.every(@polling_interval, run_now: false) do
          if update_settings(updated_settings)
            @config.logger.debug("Forked worker process #{Process.pid}: updated runtime settings from parent")
          end
        rescue => err
          @config.logger.error("Forked worker process #{Process.pid}: failed to get settings from parent: #{err.message}")
        end
      end

      def polling_start_delay
        return 0 if @polling_jitter < 1

        # Seed by pid because forked processes inherit identical PRNG state.
        Random.new(Process.pid).rand(1..@polling_jitter)
      end

      def keepalive
        @rpc_client.invoke("ping", KEEPALIVE_INTERVAL)
      rescue => err
        @config.logger.error("Forked worker process #{Process.pid}: keepalive failed: #{err.message}")
      end
    end
  end
end
