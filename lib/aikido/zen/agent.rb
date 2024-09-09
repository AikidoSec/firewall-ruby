# frozen_string_literal: true

require "concurrent"
require_relative "event"
require_relative "stats"

module Aikido::Zen
  # Handles the background processes that communicate with the Aikido servers,
  # including managing the runtime settings that keep the app protected.
  class Agent
    # @return [Aikido::Zen::Stats] the statistics collected by the agent.
    attr_reader :stats

    def initialize(
      stats: Aikido::Zen::Stats.new,
      config: Aikido::Zen.config,
      info: Aikido::Zen.info,
      api_client: Aikido::Zen::APIClient.new
    )
      @started_at = nil

      @stats = stats
      @info = info
      @config = config
      @api_client = api_client
      @timer_tasks = []
      @delayed_tasks = []
      @reporting_pool = nil
      @heartbeats = nil
    end

    def started?
      !!@started_at
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

      stats.add_attack(attack, being_blocked: @config.blocking_mode?)
      raise attack if @config.blocking_mode?
    end

    # Asynchronously reports an Event of any kind to the Aikido dashboard. If
    # given a block, the API response will be passed to the block for handling.
    #
    # @param event [Aikido::Zen::Event]
    # @yieldparam response [Object] the response from the reporting API in case
    #   of a successful request.
    #
    # @return [void]
    def report(event, &on_response)
      reporting_pool.post { @api_client.report(event).then(&on_response) }
    end

    def start!
      @config.logger.info "Starting Aikido agent"

      raise Aikido::ZenError, "Aikido Agent already started!" if started?
      @started_at = Time.now.utc

      stats.start(@started_at)

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

      # Subscribe to firewall setting changes so we can correctly re-configure
      # the heartbeat process.
      Aikido::Zen.runtime_settings.add_observer(self, :setup_heartbeat)

      at_exit { stop! if started? }

      report(Events::Started.new(time: @started_at)) do |response|
        Aikido::Zen.runtime_settings.update_from_json(response)
        @config.logger.info "Updated runtime settings."
      end

      poll_for_setting_updates
    end

    def send_heartbeat
      return unless @api_client.can_make_requests?

      flushed_stats = stats.reset
      report(Events::Heartbeat.new(stats: flushed_stats)) do |response|
        Aikido::Zen.runtime_settings.update_from_json(response)
        @config.logger.info "Updated runtime settings after heartbeat"
      end
    end

    def poll_for_setting_updates
      timer_task(every: @config.polling_interval) do
        if @api_client.should_fetch_settings?
          Aikido::Zen.runtime_settings.update_from_json(@api_client.fetch_settings)
          @config.logger.info "Updated runtime settings after polling"
        end
      end
    end

    def setup_heartbeat(settings)
      return unless @api_client.can_make_requests?

      # If the desired interval changed, then clear the current heartbeat timer
      # and set up a new one.
      if @heartbeats&.running? && @heartbeats.execution_interval != settings.heartbeat_interval
        @heartbeats.shutdown
        @heartbeats = nil
        setup_heartbeat(settings)

      # If the heartbeat timer isn't running but we know how often it should run, schedule it.
      elsif !@heartbeats&.running? && settings.heartbeat_interval&.nonzero?
        @config.logger.debug "Scheduling heartbeats every #{settings.heartbeat_interval} seconds"
        @heartbeats = timer_task(every: settings.heartbeat_interval, run_now: false) do
          send_heartbeat
        end

      elsif !@heartbeats&.running?
        @config.logger.debug(format("Heartbeat could not be setup (interval: %p)", settings.heartbeat_interval))
      end

      # If the server hasn't received any stats, we want to also run a one-off
      # heartbeat request in a minute.
      if !settings.received_any_stats
        delay(@config.initial_heartbeat_delay) { send_heartbeat if stats.any? }
      end
    end

    def stop!
      @started_at = nil

      @config.logger.info "Stopping Aikido agent"

      @timer_tasks.each { |task| task.shutdown }
      @delayed_tasks.each { |task| task.cancel if task.pending? }

      @reporting_pool&.shutdown
      @reporting_pool&.wait_for_termination(30)
    end

    private def reporting_pool
      @reporting_pool ||= Concurrent::SingleThreadExecutor.new
    end

    private def delay(delay, &task)
      Concurrent::ScheduledTask.execute(delay, executor: reporting_pool, &task)
        .tap { |task| @delayed_tasks << task }
    end

    private def timer_task(every:, **opts, &block)
      Concurrent::TimerTask.execute(
        run_now: true,
        interval_type: :fixed_rate,
        execution_interval: every,
        executor: reporting_pool,
        **opts,
        &block
      ).tap { |task| @timer_tasks << task }
    end
  end
end
