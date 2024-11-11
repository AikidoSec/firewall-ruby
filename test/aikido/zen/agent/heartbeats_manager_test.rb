# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Agent::HeartbeatsManagerTest < ActiveSupport::TestCase
  MockWorker = Struct.new(:jobs) do
    def initialize
      super([])
    end

    def every(interval, run_now: true, &task)
      MockTimer.new(running: true, interval: interval, run_now: run_now)
        .tap { |timer| jobs << timer }
    end
  end

  MockTimer = Struct.new(:running, :interval, :run_now, keyword_init: true) do
    alias_method :running?, :running
    alias_method :execution_interval, :interval

    def shutdown
      self.running = false
    end
  end

  setup do
    @worker = MockWorker.new
    @settings = Aikido::Zen.runtime_settings
    @settings.heartbeat_interval = 15

    @manager = Aikido::Zen::Agent::HeartbeatsManager.new(
      worker: @worker,
      settings: @settings
    )
  end

  test "#start schedules the block to start after the initial delay" do
    assert_difference "@worker.jobs.size", +1 do
      @manager.start { "do something" }
    end

    assert_includes @worker.jobs, MockTimer.new(running: true, interval: 15, run_now: false)
    assert_logged :debug, "Scheduling heartbeats every 15 seconds"
  end

  test "#start does not start the events twice" do
    assert_difference "@worker.jobs.size", +1 do
      @manager.start { "do something" }
      @manager.start { "do something" }
    end
  end

  test "#start does not start the timer if given a 0 delay" do
    @settings.heartbeat_interval = 0

    assert_no_difference "@worker.jobs.size" do
      @manager.start { "do something" }
    end

    assert_empty @worker.jobs
    assert_logged :warn, /Heartbeat could not be set up \(interval: 0\)/
  end

  test "#start does not start the timer if given a null delay" do
    @settings.heartbeat_interval = nil

    assert_no_difference "@worker.jobs.size" do
      @manager.start { "do something" }
    end

    assert_empty @worker.jobs
    assert_logged :warn, /Heartbeat could not be set up \(interval: nil\)/
  end

  test "#stop resets the current timer" do
    @manager.start { "do something" }

    assert_changes "@worker.jobs.first.running?", from: true, to: false do
      @manager.stop
    end
  end

  test "#stop allows for start to set up a new timer" do
    assert_difference "@worker.jobs.size", +2 do
      @manager.start { "do something" }
      @manager.stop
      @manager.start { "do something" }
    end

    # one that is no longer running, one that is now running.
    assert_includes @worker.jobs, MockTimer.new(running: false, interval: 15, run_now: false)
    assert_includes @worker.jobs, MockTimer.new(running: true, interval: 15, run_now: false)
  end

  test "#stop does nothing if not already running" do
    assert_nothing_raised do
      @manager.stop
    end
  end

  test "#restart considers changes to the interval" do
    @settings.heartbeat_interval = 10
    @manager.start { "do something" }

    @settings.heartbeat_interval = 20
    @manager.restart { "do something" }

    assert_includes @worker.jobs, MockTimer.new(running: false, interval: 10, run_now: false)
    assert_includes @worker.jobs, MockTimer.new(running: true, interval: 20, run_now: false)
  end

  test "#stale_settings? knows if it's time to restart the timer" do
    @settings.heartbeat_interval = 10

    # hasn't started yet
    refute @manager.stale_settings?

    @manager.start { "do something" }

    # interval remains the same
    refute @manager.stale_settings?

    @settings.heartbeat_interval = 20

    assert @manager.stale_settings?
  end
end
