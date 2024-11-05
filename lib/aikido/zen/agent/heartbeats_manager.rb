# frozen_string_literal: true

module Aikido::Zen
  # Handles scheduling the heartbeats we send to the Aikido servers, managing
  # runtime changes to the heartbeat interval.
  class Agent::HeartbeatsManager
    def initialize(worker:, settings: Aikido::Zen.runtime_settings, config: Aikido::Zen.config)
      @settings = settings
      @config = config
      @worker = worker

      @timer = nil
    end

    # @return [Boolean]
    def running?
      !!@timer&.running?
    end

    # @return [Boolean] whether the currently running heartbeat matches the
    #   expected interval in the runtime settings.
    def stale_settings?
      running? && @timer.execution_interval != @settings.heartbeat_interval
    end

    # Sets up the the timer to run the given block at the appropriate interval.
    # Re-entrant, and does nothing if already running.
    #
    # @return [void]
    def start(&task)
      return if running?

      if @settings.heartbeat_interval&.nonzero?
        @config.logger.debug "Scheduling heartbeats every #{@settings.heartbeat_interval} seconds"
        @timer = @worker.every(@settings.heartbeat_interval, run_now: false, &task)
      else
        @config.logger.warn(format("Heartbeat could not be set up (interval: %p)", @settings.heartbeat_interval))
      end
    end

    # Cleans up the timer.
    #
    # @return [void]
    def stop
      return unless running?

      @timer.shutdown
      @timer = nil
    end

    # Resets the timer to start with any new settings, if needed.
    #
    # @return [void]
    def restart(&task)
      stop
      start(&task)
    end

    # @api private
    #
    # @return [Integer] the current delay between events.
    def interval
      @settings.heartbeat_interval
    end
  end
end
