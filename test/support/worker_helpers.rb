module WorkerHelpers
  MockWorker = Struct.new(:recurring, :delayed) do
    def initialize
      super([], [])
    end

    def perform(&block)
      yield
    end

    def delay(interval, &block)
      MockDelayedTask.new(scheduled: true, interval: interval)
        .tap { |task| delayed << task }
    end

    def every(interval, run_now: true, &block)
      yield if run_now
      MockRecurringTask.new(scheduled: true, interval: interval, run_now: run_now, block: block)
        .tap { |task| recurring << task }
    end

    def start
      true
    end

    def stop
      recurring.each(&:cancel)
    end
  end

  MockDelayedTask = Struct.new(:scheduled, :interval, keyword_init: true) do
    alias_method :scheduled?, :scheduled

    def cancel
      self.scheduled = false
    end
  end

  MockRecurringTask = Struct.new(:scheduled, :interval, :run_now, :block, keyword_init: true) do
    alias_method :scheduled?, :scheduled

    def cancel
      self.scheduled = false
    end
  end
end
