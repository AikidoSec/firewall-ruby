# frozen_string_literal: true

require "concurrent"

module Aikido::Agent
  # Handles the background threads that are run by the Agent.
  class Runner
    def initialize(config: Aikido::Agent.config, api_client: Aikido::Agent::APIClient.new)
      @started = false
      @config = config
      @api_client = api_client
    end

    def started?
      @started
    end

    def start!
      @started = true
      poll_for_setting_updates
    end

    def poll_for_setting_updates
      timer_task(every: @config.polling_interval) do
        if @api_client.should_fetch_settings?
          Firewall.settings.update_from_json(@api_client.fetch_settings)
        end
      end
    end

    def stop!
      @poll_for_setting_updates&.kill
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
