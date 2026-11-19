# frozen_string_literal: true

require "concurrent"

module Aikido::Zen
  # @api private
  class Worker
    class Task
      # @param block [Proc] the block that cancels the scheduled work
      def initialize(&block)
        @initialize_block = block

        @cancelled = Concurrent::AtomicBoolean.new(false)
      end

      # Cancels the scheduled work once, the first time it is called.
      #
      # @return [void]
      def cancel
        @initialize_block.call if @cancelled.make_true

        nil
      end
    end

    class NotRunningError < Aikido::ZenError; end

    def initialize(config: Aikido::Zen.config)
      @config = config

      @executor = nil

      @tasks = Concurrent::Set.new

      @running = Concurrent::AtomicBoolean.new(false)
    end

    def running?
      @running.true?
    end

    def start
      return false unless @running.make_true

      @executor = Concurrent::SingleThreadExecutor.new

      # Create the thread of the executor now, instead of when the first block is queued.
      @executor.post {}

      true
    end

    def stop
      return false unless @running.make_false

      @tasks.to_a.each(&:cancel)

      @executor.shutdown
      @executor.wait_for_termination(30)

      true
    end

    # Queue a block to be run asynchronously.
    #
    # @return [void]
    # @raise [NotRunningError] if the worker is not running
    def perform(&block)
      ensure_running

      @executor.post { run(&block) }
    end

    # Queue a block to be run asynchronously, after +interval+ seconds.
    #
    # @param interval [Integer] the number of seconds to wait before running
    # @return [Task]
    # @raise [NotRunningError] if the worker is not running
    def delay(interval, &block)
      ensure_running

      deferral = Concurrent::ScheduledTask.execute(
        interval,
        executor: @executor
      ) do
        run(&block)
      end

      schedule { deferral.cancel }
    end

    # Queue a block to be run asynchronously, every +interval+ seconds.
    #
    # If a run takes longer than that, the next run starts immediately.
    #
    # @param interval [Integer] the number of seconds between runs
    # @param run_now [Boolean] whether to also run the block immediately
    # @return [Task]
    # @raise [NotRunningError] if the worker is not running
    def every(interval, run_now: true, &block)
      ensure_running

      timer = Concurrent::TimerTask.execute(
        executor: @executor,
        run_now: run_now,
        execution_interval: interval,
        interval_type: :fixed_rate
      ) do
        run(&block)
      end

      schedule { timer.shutdown }
    end

    private

    def ensure_running
      raise NotRunningError, "The worker is not running" unless running?
    end

    def run
      yield
    rescue Exception => err # rubocop:disable Lint/RescueException
      @config.logger.error("Error in background worker: #{err.class}: #{err.message}")
      @config.logger.debug(err.backtrace.join("\n"))
    end

    def schedule(&cancel)
      task = Task.new do
        @tasks.delete(task)
        cancel.call
      end

      @tasks << task

      task
    end
  end
end
