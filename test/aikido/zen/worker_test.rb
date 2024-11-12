# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::WorkerTest < ActiveSupport::TestCase
  setup { @worker = Aikido::Zen::Worker.new }

  # Forces the block to run within an immediate executor (i.e. synchronously)
  # rather than in the background thread.
  def sync(&block)
    @worker.stub(:executor, Concurrent::ImmediateExecutor.new, &block)
  end

  test "#perform runs the given block" do
    value = 1

    sync do
      @worker.perform { value += 1 }
    end

    assert_equal 2, value
  end

  test "#perform catches and logs exceptions but does not raise" do
    sync do
      assert_nothing_raised do
        @worker.perform { raise "nope" }
      end

      assert_logged :error, "Error in background worker: #<RuntimeError: nope>"
    end
  end

  test "#delay queues a deferred task" do
    task = nil

    assert_difference "@worker.deferrals.size", +1 do
      task = @worker.delay(5) { "a task" }
    end

    assert_kind_of Concurrent::ScheduledTask, task
    assert_equal 5, task.initial_delay
    assert task.pending?
  ensure
    task.cancel
  end

  test "#delay catches and logs exceptions in its task" do
    sync do
      assert_nothing_raised do
        @worker.delay(0) { raise "delayed nope" }
      end

      assert_logged :error, "Error in background worker: #<RuntimeError: delayed nope>"
    end
  end

  test "#every queues a recurring task on a timer" do
    task = nil

    assert_difference "@worker.timers.size", +1 do
      task = @worker.every(5) { "a task" }
    end

    assert_kind_of Concurrent::TimerTask, task
    assert_equal 5, task.execution_interval
    assert task.running?
  ensure
    task.shutdown
  end

  test "#every runs the task immediately by default" do
    value = 0

    sync do
      task = @worker.every(5) { value += 1 }
      assert_equal 1, value
    ensure
      task.shutdown
    end
  end

  test "#every does not run the task immediately if told so" do
    value = 0

    sync do
      task = @worker.every(5, run_now: false) { value += 1 }
      assert_equal 0, value
    ensure
      task.shutdown
    end
  end

  test "#every catches and logs exceptions in its task" do
    assert_nothing_raised do
      sync do
        task = @worker.every(5) { raise "recurring nope" }
      ensure
        task.shutdown
      end
    end

    assert_logged :error, "Error in background worker: #<RuntimeError: recurring nope>"
  end

  test "#shutdown kills any pending deferred tasks" do
    task = Minitest::Mock.new
    task.expect :pending?, true
    task.expect :cancel, nil

    @worker.deferrals << task
    @worker.shutdown

    assert_mock task
  end

  test "#shutdown ignores deferred tasks that have already executed" do
    task = Minitest::Mock.new
    task.expect :pending?, false

    @worker.deferrals << task
    @worker.shutdown

    assert_mock task
  end

  test "#shutdown kills any timer task" do
    task = Minitest::Mock.new
    task.expect :shutdown, nil

    @worker.timers << task
    @worker.shutdown

    assert_mock task
  end
end
