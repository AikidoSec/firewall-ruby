module WorkerHelpers
  MockWorker = Struct.new(:jobs, :delayed, :restarted) do
    def initialize
      super([], [], false)
    end

    def perform(&block)
      yield
    end

    def delay(interval, &block)
      MockDefer.new(queued: true, interval: interval)
        .tap { |task| delayed << task }
    end

    def every(interval, run_now: true, &task)
      yield if run_now
      MockTimer.new(running: true, interval: interval, run_now: run_now)
        .tap { |timer| jobs << timer }
    end

    def shutdown
      jobs.each(&:shutdown)
    end

    def restart
      jobs.clear
      self[:restarted] = true
    end
  end

  MockDefer = Struct.new(:queued, :interval, keyword_init: true) do
    alias_method :pending?, :queued
    alias_method :initial_delay, :interval

    def cancel
      self.queued = false
    end
  end

  MockTimer = Struct.new(:running, :interval, :run_now, keyword_init: true) do
    alias_method :running?, :running
    alias_method :execution_interval, :interval

    def shutdown
      self.running = false
    end
  end
end
