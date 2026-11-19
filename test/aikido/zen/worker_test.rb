# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::WorkerTest < ActiveSupport::TestCase
  setup do
    @worker = Aikido::Zen::Worker.new
    @worker.start
  end

  teardown do
    @worker.stop
  end

  def executor_of(worker)
    worker.instance_variable_get(:@executor)
  end

  def tasks
    @worker.instance_variable_get(:@tasks)
  end

  # Registers a task that runs the block when it is cancelled.
  def schedule(&cancel)
    @worker.send(:schedule, &cancel)
  end

  # Runs the block with the worker on an immediate executor, so that it runs
  # tasks synchronously rather than in the background thread.
  def with_immediate_executor
    previous_executor = executor_of(@worker)
    @worker.instance_variable_set(:@executor, Concurrent::ImmediateExecutor.new)

    yield
  ensure
    @worker.instance_variable_set(:@executor, previous_executor)
  end

  test "a new worker is not running" do
    worker = Aikido::Zen::Worker.new

    refute worker.running?
  end

  test "a new worker has no executor" do
    worker = Aikido::Zen::Worker.new

    assert_nil executor_of(worker)
  end

  test "#start starts the worker" do
    worker = Aikido::Zen::Worker.new

    assert worker.start

    assert worker.running?
  ensure
    worker.stop
  end

  test "#start creates the thread of its executor" do
    worker = Aikido::Zen::Worker.new

    worker.start

    assert_equal 1, executor_of(worker).length
  ensure
    worker.stop
  end

  test "#start does nothing if the worker is already running" do
    executor = executor_of(@worker)

    refute @worker.start

    assert_same executor, executor_of(@worker)
  end

  test "#stop stops the worker" do
    assert @worker.stop

    refute @worker.running?
  end

  test "#stop cancels its tasks" do
    cancellations = 0
    schedule { cancellations += 1 }

    @worker.stop

    assert_equal 1, cancellations
  end

  test "#stop waits for a running block to finish" do
    started = Queue.new
    release = Queue.new
    finished = false
    @worker.delay(0) do
      started << true
      release.pop
      finished = true
    end
    Timeout.timeout(2) { started.pop }

    stopper = Thread.new { @worker.stop }

    assert_nil stopper.join(0.2)

    release << true
    stopper.join(2)

    assert finished
  end

  test "#stop does nothing if the worker is not running" do
    worker = Aikido::Zen::Worker.new

    refute worker.stop
  end

  test "#stop does nothing if the worker has already been stopped" do
    assert @worker.stop
    refute @worker.stop
  end

  test "#start starts a stopped worker again" do
    @worker.stop

    assert @worker.start

    assert @worker.running?
  end

  test "#start gives a stopped worker a new executor, with its thread" do
    previous_executor = executor_of(@worker)

    @worker.stop
    @worker.start

    refute_same previous_executor, executor_of(@worker)
    assert_equal 1, executor_of(@worker).length
  end

  test "#perform runs the block" do
    value = 1

    with_immediate_executor do
      @worker.perform { value += 1 }
    end

    assert_equal 2, value
  end

  test "#perform catches and logs exceptions in its block" do
    with_immediate_executor do
      assert_nothing_raised do
        @worker.perform { raise "nope" }
      end

      assert_logged :error, "Error in background worker: RuntimeError: nope"
    end
  end

  test "#perform raises NotRunningError if the worker has not been started" do
    worker = Aikido::Zen::Worker.new

    assert_raises(Aikido::Zen::Worker::NotRunningError) do
      worker.perform { "some work" }
    end
  end

  test "#perform raises NotRunningError if the worker is stopped" do
    @worker.stop

    assert_raises(Aikido::Zen::Worker::NotRunningError) do
      @worker.perform { "some work" }
    end
  end

  test "#delay schedules a task" do
    assert_difference "tasks.size", +1 do
      @worker.delay(5) { "some work" }
    end
  end

  test "#delay returns a Task for cancellation" do
    task = @worker.delay(5) { "some work" }

    assert_kind_of Aikido::Zen::Worker::Task, task
    assert_respond_to task, :cancel
  end

  test "#delay runs the block" do
    ran = Queue.new

    @worker.delay(0.05) { ran << true }

    assert Timeout.timeout(2) { ran.pop }
  end

  test "#delay catches and logs exceptions in its block" do
    with_immediate_executor do
      assert_nothing_raised do
        @worker.delay(0) { raise "delayed nope" }
      end

      assert_logged :error, "Error in background worker: RuntimeError: delayed nope"
    end
  end

  test "#delay raises NotRunningError if the worker has not been started" do
    worker = Aikido::Zen::Worker.new

    assert_raises(Aikido::Zen::Worker::NotRunningError) do
      worker.delay(5) { "some work" }
    end
  end

  test "#delay raises NotRunningError if the worker is stopped" do
    @worker.stop

    assert_raises(Aikido::Zen::Worker::NotRunningError) do
      @worker.delay(5) { "some work" }
    end
  end

  test "#delay runs the block itself, without queueing it again" do
    ran = Queue.new
    queued = false

    @worker.stub(:perform, ->(&_work) { queued = true }) do
      @worker.delay(0.05) { ran << true }

      assert Timeout.timeout(2) { ran.pop }
    end

    refute queued
  end

  test "#every schedules a task" do
    assert_difference "tasks.size", +1 do
      @worker.every(5, run_now: false) { "some work" }
    end
  end

  test "#every returns a Task for cancellation" do
    task = @worker.every(5, run_now: false) { "some work" }

    assert_kind_of Aikido::Zen::Worker::Task, task
    assert_respond_to task, :cancel
  end

  test "#every runs the block repeatedly" do
    runs = Queue.new

    @worker.every(0.05, run_now: false) { runs << true }

    2.times { assert Timeout.timeout(2) { runs.pop } }
  end

  test "#every runs the block immediately by default" do
    value = 0

    with_immediate_executor do
      @worker.every(5) { value += 1 }

      assert_equal 1, value
    end
  end

  test "#every does not run the block immediately when run_now is false" do
    value = 0

    with_immediate_executor do
      @worker.every(5, run_now: false) { value += 1 }

      assert_equal 0, value
    end
  end

  test "#every catches and logs exceptions in its block" do
    assert_nothing_raised do
      with_immediate_executor do
        @worker.every(5) { raise "recurring nope" }
      end
    end

    assert_logged :error, "Error in background worker: RuntimeError: recurring nope"
  end

  test "#every raises NotRunningError if the worker has not been started" do
    worker = Aikido::Zen::Worker.new

    assert_raises(Aikido::Zen::Worker::NotRunningError) do
      worker.every(5) { "some work" }
    end
  end

  test "#every raises NotRunningError if the worker is stopped" do
    @worker.stop

    assert_raises(Aikido::Zen::Worker::NotRunningError) do
      @worker.every(5) { "some work" }
    end
  end

  test "#every runs the block itself, without queueing it again" do
    ran = Queue.new
    queued = false

    @worker.stub(:perform, ->(&_work) { queued = true }) do
      @worker.every(0.05, run_now: false) { ran << true }

      assert Timeout.timeout(2) { ran.pop }
    end

    refute queued
  end

  test "Task#cancel removes a delayed task" do
    task = @worker.delay(5) { "some work" }

    assert_difference "tasks.size", -1 do
      task.cancel
    end
  end

  test "Task#cancel removes a recurring task" do
    task = @worker.every(5, run_now: false) { "some work" }

    assert_difference "tasks.size", -1 do
      task.cancel
    end
  end

  test "Task#cancel removes a delayed task that has already run" do
    task = nil

    with_immediate_executor do
      task = @worker.delay(0) { "some work" }
    end

    assert_difference "tasks.size", -1 do
      assert_nothing_raised { task.cancel }
    end
  end

  test "Task#cancel prevents a delayed task from running" do
    ran = false
    task = @worker.delay(0.1) { ran = true }

    task.cancel

    sleep 0.3

    refute ran
  end

  test "Task#cancel prevents a recurring task from running again" do
    runs = Queue.new
    task = @worker.every(0.05, run_now: false) { runs << true }

    assert Timeout.timeout(2) { runs.pop }

    task.cancel

    sleep 0.2
    runs.clear
    sleep 0.2

    assert_empty runs
  end

  test "Task#cancel does not return the result of its cancellation" do
    assert_nil Aikido::Zen::Worker::Task.new { true }.cancel
    assert_nil Aikido::Zen::Worker::Task.new { false }.cancel
  end

  test "Task#cancel only runs its cancellation the first time" do
    cancellations = 0
    task = Aikido::Zen::Worker::Task.new { cancellations += 1 }

    task.cancel

    assert_equal 1, cancellations

    assert_no_difference -> { cancellations } do
      task.cancel
    end
  end

  test "Task#cancel only runs its cancellation once when called from multiple threads" do
    cancellations = Concurrent::AtomicFixnum.new(0)
    task = Aikido::Zen::Worker::Task.new { cancellations.increment }

    10.times.map { Thread.new { task.cancel } }.each(&:join)

    assert_equal 1, cancellations.value
  end

  test "Task#cancel does not run its cancellation again after #stop cancelled the task" do
    cancellations = 0
    task = schedule { cancellations += 1 }

    @worker.stop

    assert_equal 1, cancellations

    assert_no_difference -> { cancellations } do
      task.cancel
    end
  end

  test "Task#cancel does not cancel the other tasks of the worker" do
    ran = Queue.new
    @worker.delay(0.1) { ran << true }
    task = @worker.every(5, run_now: false) { "some work" }

    task.cancel

    assert_equal 1, tasks.size
    assert Timeout.timeout(2) { ran.pop }
  end
end
