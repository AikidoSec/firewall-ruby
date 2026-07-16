# frozen_string_literal: true

require "concurrent"
require_relative "event"
require_relative "config"
require_relative "system_info"

module Aikido::Zen
  # Handles the background processes that communicate with the Aikido servers,
  # including managing the runtime settings that keep the app protected.
  class Agent
    # Initialize and start an agent instance.
    #
    # @return [Aikido::Zen::Agent]
    def self.start(**opts)
      new(**opts).tap(&:start!)
    end

    def initialize(
      config: Aikido::Zen.config,
      collector: Aikido::Zen.collector,
      worker: Aikido::Zen::Worker.new(config: config),
      api_client: Aikido::Zen::APIClient.new(config: config),
      api_stream: Aikido::Zen::APIStream.new(config: config)
    )
      @config = config
      @collector = collector
      @worker = worker
      @api_client = api_client
      @api_stream = api_stream

      @started_at = nil

      @runtime_config_update_mutex = Mutex.new
      @runtime_firewall_lists_update_mutex = Mutex.new
    end

    def started?
      !!@started_at
    end

    def start!
      @config.logger.info("Starting Aikido agent v#{Aikido::Zen::VERSION}")

      raise Aikido::ZenError, "Aikido Agent already started!" if started?
      @started_at = Time.now.utc
      @collector.start(at: @started_at)

      if Aikido::Zen.blocking_mode?
        @config.logger.info("Requests identified as attacks will be blocked")
      else
        @config.logger.warn("Non-blocking mode enabled! No requests will be blocked")
      end

      if @api_client.can_make_requests?
        @config.logger.info("API Token set! Reporting has been enabled")
      else
        @config.logger.warn("No API Token set! Reporting has been disabled")
        return
      end

      at_exit { stop! if started? }

      report(Events::Started.new(time: @started_at)) do |response|
        if update_settings_from_runtime_config!(response, reason: "after start")
          updated_settings!
        end
      rescue => err
        @config.logger.error(err.message)
      end

      begin
        update_settings_from_runtime_firewall_lists!(@api_client.fetch_runtime_firewall_lists, reason: "after start")
      rescue => err
        @config.logger.error(err.message)
      end

      if @config.realtime_settings_updates_enabled?
        @api_stream.handle("config-updated") do |event|
          @config.logger.debug("Received server-sent event: config-updated")
          settings_updated(event)
        end

        @api_stream.start!
      end

      poll_for_setting_updates

      @config.initial_heartbeat_delays.each do |heartbeat_delay|
        @worker.delay(heartbeat_delay) do
          send_heartbeat
          @config.logger.info("Executed initial heartbeat after #{heartbeat_delay} seconds")
        end
      end
    end

    # Clean up any ongoing threads, and reset the state. Called automatically
    # when the process exits.
    #
    # @return [void]
    def stop!
      @config.logger.info("Stopping Aikido agent")
      @started_at = nil
      @worker.shutdown

      @api_stream.stop!
    end

    # Respond to the runtime settings changing after being fetched from the
    # Aikido servers.
    #
    # @return [void]
    def updated_settings!
      if !heartbeats.running?
        heartbeats.start { send_heartbeat }
      elsif heartbeats.stale_settings?
        heartbeats.restart { send_heartbeat }
      end
    end

    # Given an Attack, report it to the Aikido server, and/or block the request
    # depending on configuration.
    #
    # @param attack [Attack] a detected attack.
    # @return [void]
    #
    # @raise [Aikido::Zen::UnderAttackError] if the firewall is configured
    #   to block requests.
    def handle_attack(attack)
      attack.will_be_blocked! if Aikido::Zen.blocking_mode?

      @config.logger.error(
        format("Zen has %s a %s: %s", attack.blocked? ? "blocked" : "detected", attack.humanized_name, attack.as_json.to_json)
      )
      report(Events::Attack.new(attack: attack)) if @api_client.can_make_requests?

      @collector.track_attack(attack)
      raise attack if attack.blocked?
    end

    # Asynchronously reports an Event of any kind to the Aikido dashboard. If
    # given a block, the API response will be passed to the block for handling.
    #
    # @param event [Aikido::Zen::Event]
    # @yieldparam response [Object] the response from the reporting API in case
    #   of a successful request.
    #
    # @return [void]
    def report(event)
      @worker.perform do
        response = @api_client.report(event)
        yield response if response && block_given?
      rescue Aikido::Zen::APIError, Aikido::Zen::NetworkError => err
        @config.logger.error(err.message)
      end
    end

    # @api private
    #
    # Atomically flushes all the stats stored by the agent, and sends a
    # heartbeat event. Scheduled to run automatically on a recurring schedule
    # when reporting is enabled.
    #
    # @param at [Time] the event time. Defaults to now.
    # @return [void]
    # @see Aikido::Zen::RuntimeSettings#heartbeat_interval
    def send_heartbeat(at: Time.now.utc)
      return unless @api_client.can_make_requests?

      heartbeat = @collector.flush
      report(heartbeat) do |response|
        if update_settings_from_runtime_config!(response, reason: "after heartbeat")
          updated_settings!

          update_settings_from_runtime_firewall_lists!(@api_client.fetch_runtime_firewall_lists, reason: "after heartbeat")
        end
      end
    end

    # @api private
    #
    # Sets up the timer task that polls the Aikido Runtime API for updates to
    # the runtime settings every minute.
    #
    # @return [void]
    # @see Aikido::Zen::RuntimeSettings
    def poll_for_setting_updates
      @worker.every(@config.polling_interval) do
        if @api_client.should_fetch_settings?
          if update_settings_from_runtime_config!(@api_client.fetch_runtime_config, reason: "after polling")
            updated_settings!
          end

          update_settings_from_runtime_firewall_lists!(@api_client.fetch_runtime_firewall_lists, reason: "after polling")
        end
      end
    end

    private

    def settings_updated(event)
      updated_at = Time.at(event[:data]["configUpdatedAt"].to_i)

      if should_fetch_settings?(updated_at)
        if update_settings_from_runtime_config!(@api_client.fetch_runtime_config, reason: "after server-sent event")
          updated_settings!

          update_settings_from_runtime_firewall_lists!(@api_client.fetch_runtime_firewall_lists, reason: "after server-sent event")
        end
      end
    end

    def should_fetch_settings?(updated_at, last_updated_at = Aikido::Zen.runtime_settings.updated_at)
      return false unless @api_client.can_make_requests?
      return true if last_updated_at.nil?

      updated_at > last_updated_at
    end

    def heartbeats
      @heartbeats ||= Aikido::Zen::Agent::HeartbeatsManager.new(
        config: @config,
        worker: @worker
      )
    end

    # @param data [Hash]
    # @param reason [String] context appended to the log message when logged
    # @return [Boolean]
    def update_settings_from_runtime_config!(data, reason:)
      return unless @runtime_config_update_mutex.try_lock
      begin
        return false unless Aikido::Zen.api_cache.update_runtime_config(data)

        result = Aikido::Zen.runtime_settings.update_from_runtime_config_json(data)
        @config.logger.info("Updated runtime settings #{reason}") if result
        result
      ensure
        @runtime_config_update_mutex.unlock
      end
    end

    # @param data [Hash]
    # @param reason [String] context appended to the log message when logged
    # @return [Boolean]
    def update_settings_from_runtime_firewall_lists!(data, reason:)
      return unless @runtime_firewall_lists_update_mutex.try_lock
      begin
        return false unless Aikido::Zen.api_cache.update_runtime_firewall_lists(data)

        result = Aikido::Zen.runtime_settings.update_from_runtime_firewall_lists_json(data)
        @config.logger.info("Updated runtime firewall list #{reason}") if result
        result
      ensure
        @runtime_firewall_lists_update_mutex.unlock
      end
    end
  end
end

require_relative "agent/heartbeats_manager"
