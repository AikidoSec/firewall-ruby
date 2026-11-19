# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Agent::HeartbeatsManagerTest < ActiveSupport::TestCase
  include WorkerHelpers

  setup do
    @worker = MockWorker.new
    @settings = Aikido::Zen.runtime_settings
    @settings.heartbeat_interval = 15

    @manager = Aikido::Zen::Agent::HeartbeatsManager.new(
      worker: @worker,
      settings: @settings
    )
  end

  # The [interval, scheduled?, run_now] of each recurring task, in the order that
  # they were scheduled.
  def heartbeat_tasks
    @worker.recurring.map { |task| [task.interval, task.scheduled?, task.run_now] }
  end

  test "#start schedules the block to start after the initial delay" do
    assert_difference "@worker.recurring.size", +1 do
      @manager.start { "do something" }
    end

    assert_equal [[15, true, false]], heartbeat_tasks
    assert_logged :debug, "Scheduling heartbeats every 15 seconds"
  end

  test "#start does not start the events twice" do
    assert_difference "@worker.recurring.size", +1 do
      @manager.start { "do something" }
      @manager.start { "do something" }
    end
  end

  test "#start does not start the timer if given a 0 delay" do
    @settings.heartbeat_interval = 0

    assert_no_difference "@worker.recurring.size" do
      @manager.start { "do something" }
    end

    assert_empty @worker.recurring
    assert_logged :warn, /Heartbeat could not be set up \(interval: 0\)/
  end

  test "#start does not start the timer if given a null delay" do
    @settings.heartbeat_interval = nil

    assert_no_difference "@worker.recurring.size" do
      @manager.start { "do something" }
    end

    assert_empty @worker.recurring
    assert_logged :warn, /Heartbeat could not be set up \(interval: nil\)/
  end

  test "#stop resets the current timer" do
    @manager.start { "do something" }

    assert_changes "@worker.recurring.first.scheduled?", from: true, to: false do
      @manager.stop
    end
  end

  test "#stop allows for start to set up a new timer" do
    assert_difference "@worker.recurring.size", +2 do
      @manager.start { "do something" }
      @manager.stop
      @manager.start { "do something" }
    end

    assert_equal [[15, false, false], [15, true, false]], heartbeat_tasks
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

    assert_equal [[10, false, false], [20, true, false]], heartbeat_tasks
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
