# frozen_string_literal: true

require "concurrent"
require_relative "event"

module Aikido::Agent
  # Handles the background threads that are run by the Agent.
  class Runner
    def initialize(
      config: Aikido::Agent.config,
      info: Aikido::Agent.info,
      api_client: Aikido::Agent::APIClient.new
    )
      @started_at = nil

      @info = info
      @config = config
      @api_client = api_client
      @timer_tasks = []
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
    # @raise [Aikido::Firewall::UnderAttackError] if the firewall is configured
    #   to block requests.
    def handle_attack(attack)
      @config.logger.error("[ATTACK DETECTED] #{attack.log_message}")
      report(Events::Attack.new(attack: attack)) if @api_client.can_make_requests?

      raise attack if @config.blocking_mode?
    end

    # Asynchronously reports an Event of any kind to the Aikido dashboard. If
    # given a block, the API response will be passed to the block for handling.
    #
    # @param event [Aikido::Agent::Event]
    # @yieldparam response [Object] the response from the reporting API in case
    #   of a successful request.
    #
    # @return [void]
    def report(event, &on_response)
      reporting_pool.post { @api_client.report(event).then(&on_response) }
    end

    def start!
      @config.logger.info "Starting Aikido agent"

      raise Aikido::AgentError, "Aikido Agent already started!" if started?
      @started_at = Time.now.utc

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
        Aikido::Firewall.settings.update_from_json(response)
        @config.logger.info "Updated firewall settings."
      end

      poll_for_setting_updates
    end

    def poll_for_setting_updates
      timer_task(every: @config.polling_interval) do
        if @api_client.should_fetch_settings?
          Aikido::Firewall.settings.update_from_json(@api_client.fetch_settings)
          @config.logger.info "Updated firewall settings after polling"
        end
      end
    end

    def stop!
      @started_at = nil

      @config.logger.info "Stopping Aikido agent"

      @timer_tasks.each { |task| task.shutdown }

      @reporting_pool&.shutdown
      @reporting_pool&.wait_for_termination(30)
    end

    private def reporting_pool
      @reporting_pool ||= Concurrent::SingleThreadExecutor.new
    end

    private def timer_task(every:, **opts, &block)
      @timer_tasks << Concurrent::TimerTask.execute(
        run_now: true,
        interval_type: :fixed_rate,
        execution_interval: every,
        executor: reporting_pool,
        **opts,
        &block
      )
    end
  end
end
