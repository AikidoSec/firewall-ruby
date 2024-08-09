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
    end

    def started?
      !!@started_at
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
      raise AgentError, "Aikido Agent already started!" if started?
      @started_at = Time.now.utc

      report(Events::Started.new(time: @started_at)) do |response|
        Aikido::Firewall.settings.update_from_json(settings)
      end

      poll_for_setting_updates
    end

    def poll_for_setting_updates
      @poll_for_setting_updates = timer_task(every: @config.polling_interval) do
        if @api_client.should_fetch_settings?
          Aikido::Firewall.settings.update_from_json(@api_client.fetch_settings)
        end
      end
    end

    def stop!
      @poll_for_setting_updates&.kill
      @reporting_pool&.shutdown and @reporting_pool&.wait_for_termination(30)
    end

    private def reporting_pool
      @reporting_pool ||= Concurrent::SingleThreadExecutor.new
    end

    private def timer_task(every:, **opts, &block)
      task = Concurrent::TimerTask.new(
        run_now: true,
        interval_type: :fixed_rate,
        execution_interval: every,
        **opts,
        &block
      )

      task.execute
      task
    end
  end
end
