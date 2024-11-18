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
      api_client: Aikido::Zen::APIClient.new(config: config)
    )
      @started_at = nil

      @config = config
      @worker = worker
      @api_client = api_client
      @collector = collector
    end

    def started?
      !!@started_at
    end

    def start!
      @config.logger.info "Starting Aikido agent"

      raise Aikido::ZenError, "Aikido Agent already started!" if started?
      @started_at = Time.now.utc
      @collector.start(at: @started_at)

      if @config.blocking_mode?
        @config.logger.info "Requests identified as attacks will be blocked"
      else
        @config.logger.warn "Non-blocking mode enabled! No requests will be blocked."
      end

      if @api_client.can_make_requests?
        @config.logger.info "API Token set! Reporting has been enabled."
      else
        @config.logger.warn "No API Token set! Reporting has been disabled."
        return
      end

      at_exit { stop! if started? }

      report(Events::Started.new(time: @started_at)) do |response|
        Aikido::Zen.runtime_settings.update_from_json(response)
        @config.logger.info "Updated runtime settings."
      rescue => err
        @config.logger.error(err.message)
      end

      poll_for_setting_updates

      @worker.delay(@config.initial_heartbeat_delay) do
        send_heartbeat if @collector.stats.any?
      end
    end

    # Clean up any ongoing threads, and reset the state. Called automatically
    # when the process exits.
    #
    # @return [void]
    def stop!
      @config.logger.info "Stopping Aikido agent"
      @started_at = nil
      @worker.shutdown
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
      attack.will_be_blocked! if @config.blocking_mode?

      @config.logger.error("[ATTACK DETECTED] #{attack.log_message}")
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

      event = @collector.flush(at: at)

      report(event) do |response|
        Aikido::Zen.runtime_settings.update_from_json(response)
        @config.logger.info "Updated runtime settings after heartbeat"
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
          Aikido::Zen.runtime_settings.update_from_json(@api_client.fetch_settings)
          @config.logger.info "Updated runtime settings after polling"
        end
      end
    end

    private def heartbeats
      @heartbeats ||= Aikido::Zen::Agent::HeartbeatsManager.new(
        config: @config,
        worker: @worker
      )
    end
  end
end

require_relative "agent/heartbeats_manager"
