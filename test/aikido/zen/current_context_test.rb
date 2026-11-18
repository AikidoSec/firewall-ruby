# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::CurrentContextTest < ActiveSupport::TestCase
  setup do
    @context = Object.new
    Aikido::Zen.current_context = @context
  end

  teardown do
    Aikido::Zen.current_context = nil
  end

  class BlockPassingThread < Thread
    def initialize(&work)
      super
    end
  end

  class OwnBlockThread < Thread
    def initialize
      super { Aikido::Zen.current_context }
    end
  end

  class OwnBlockArgumentsThread < Thread
    def initialize(*args, **kwargs)
      super { |*received, **received_kwargs| [received, received_kwargs] }
    end
  end

  test "a Fiber created with Fiber.new inherits the current context" do
    assert_same @context, Fiber.new { Aikido::Zen.current_context }.resume
  end

  test "a Thread created with Thread.new inherits the current context" do
    assert_same @context, Thread.new { Aikido::Zen.current_context }.value
  end

  test "a Thread created with Thread.start inherits the current context" do
    assert_same @context, Thread.start { Aikido::Zen.current_context }.value
  end

  test "a Thread created with Thread.fork inherits the current context" do
    assert_same @context, Thread.fork { Aikido::Zen.current_context }.value
  end

  test "a Thread subclass created with a block inherits the current context" do
    assert_same @context, BlockPassingThread.new { Aikido::Zen.current_context }.value
  end

  test "a Thread subclass with its own block inherits the current context" do
    assert_same @context, OwnBlockThread.new.value
  end

  test "a Thread subclass with its own block is given its arguments" do
    assert_equal [[1, 2], {k: 3}], OwnBlockArgumentsThread.new(1, 2, k: 3).value
  end

  test "a Thread created with no current context has no current context" do
    Aikido::Zen.current_context = nil

    assert_nil Thread.new { Aikido::Zen.current_context }.value
  end

  test "a Thread created with Thread.new is given its arguments" do
    assert_equal [[1, 2], {k: 3}], Thread.new(1, 2, k: 3) { |*args, **kwargs| [args, kwargs] }.value
  end

  test "a Thread created with Thread.start is given its arguments" do
    assert_equal [[1, 2], {k: 3}], Thread.start(1, 2, k: 3) { |*args, **kwargs| [args, kwargs] }.value
  end

  test "a Thread created with Thread.new returns the value of its block" do
    assert_equal :done, Thread.new { :done }.value
  end

  test "Thread.new without a block raises" do
    assert_raises(ThreadError) { Thread.new }
  end

  test "Thread.start without a block raises" do
    assert_raises(ArgumentError) { Thread.start }
  end

  test "Thread.fork without a block raises" do
    assert_raises(ArgumentError) { Thread.fork }
  end

  test "the current context of a created Thread does not affect the creating Thread" do
    other = Object.new

    Thread.new { Aikido::Zen.current_context = other }.join

    assert_same @context, Aikido::Zen.current_context
  end

  test "a Thread inside a Thread inherits the current context" do
    assert_same @context, Thread.new { Thread.new { Aikido::Zen.current_context }.value }.value
  end

  test "a Thread inherits the context that was current when it was created, not when it runs" do
    ready = Queue.new
    thread = Thread.new do
      ready.pop
      Aikido::Zen.current_context
    end

    Aikido::Zen.current_context = Object.new
    ready << true

    assert_same @context, thread.value
  end

  test "a Thread created in a Fiber inherits the current context of the Fiber" do
    other = Object.new

    context = Fiber.new do
      Aikido::Zen.current_context = other

      Thread.new { Aikido::Zen.current_context }.value
    end.resume

    assert_same other, context
  end

  test "a thread pool inherits the context that is current when its thread is created" do
    executor = Concurrent::SingleThreadExecutor.new
    contexts = Queue.new

    executor.post { contexts << Aikido::Zen.current_context }

    assert_same @context, contexts.pop
  ensure
    executor.shutdown
    executor.wait_for_termination(5)
  end

  test "a worker started with no context runs blocks with no context, whatever the context of the request that queues them" do
    Aikido::Zen.current_context = nil
    worker = Aikido::Zen::Worker.new
    worker.start
    contexts = Queue.new

    Aikido::Zen.current_context = @context
    worker.perform { contexts << Aikido::Zen.current_context }

    assert_nil contexts.pop
  ensure
    worker.stop
  end

  test "a worker started with a context runs blocks with that context" do
    worker = Aikido::Zen::Worker.new
    worker.start
    contexts = Queue.new

    worker.perform { contexts << Aikido::Zen.current_context }

    assert_same @context, contexts.pop
  ensure
    worker.stop
  end
end
