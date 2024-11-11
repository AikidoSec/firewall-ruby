# frozen_string_literal: true

require "concurrent"

module Aikido::Zen
  # @api private
  #
  # The worker manages the background thread in which Zen communicates with the
  # Aikido server.
  class Worker
    # @return [Concurrent::ExecutorService]
    attr_reader :executor

    # @!visibility private
    attr_reader :timers, :deferrals

    def initialize(config: Aikido::Zen.config)
      @config = config
      @timers = []
      @deferrals = []
      @executor = Concurrent::SingleThreadExecutor.new
    end

    # Queue a block to be run asynchronously in the background thread.
    #
    # @return [void]
    def perform(&block)
      executor.post do
        yield
      rescue Exception => err # rubocop:disable Lint/RescueException
        @config.logger.error "Error in background worker: #{err.inspect}"
      end
    end

    # Queue a block to be run asynchronously after a delay.
    #
    # @param interval [Integer] amount of seconds to wait.
    # @return [void]
    def delay(interval, &task)
      Concurrent::ScheduledTask
        .execute(interval, executor: executor) { perform(&task) }
        .tap { |deferral| @deferrals << deferral }
    end

    # Queue a block to run repeatedly on a timer on the background thread. The
    # timer will consider how long the block takes to run to schedule the next
    # run. For example, if you schedule a block to run every 10 seconds, and the
    # block itself takes 2 seconds, the second iteration will be run 8 seconds
    # after the first one.
    #
    # If the block takes longer than the given interval, the second iteration
    # will be run immediately.
    #
    # @param interval [Integer] amount of seconds to wait between runs.
    # @param run_now [Boolean] whether to run the block immediately, or wait for
    #   +interval+ seconds before the first run. Defaults to +true+.
    # @return [void]
    def every(interval, run_now: true, &task)
      Concurrent::TimerTask
        .execute(
          run_now: run_now,
          executor: executor,
          interval_type: :fixed_rate,
          execution_interval: interval
        ) {
          perform(&task)
        }
        .tap { |timer| @timers << timer }
    end

    # Safely clean up and kill the thread, giving time to kill any ongoing tasks
    # on the queue.
    #
    # @return [void]
    def shutdown
      @deferrals.each { |task| task.cancel if task.pending? }
      @timers.each { |task| task.shutdown }
      @executor.shutdown
      @executor.wait_for_termination(30)
    end
  end
end
