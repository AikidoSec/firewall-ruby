require "test_helper"

# Records the context that is current when a Thread is created, when recording.
class Thread
  alias_method :initialize__internal_for_active_job_test, :initialize

  def initialize(...)
    ActiveJobTest.thread_contexts&.push(Aikido::Zen.current_context)

    initialize__internal_for_active_job_test(...)
  end
end

# The ActiveJob async adapter creates a thread when a job is enqueued and no
# thread in the thread pool is idle. A job must run with the context that it
# was enqueued in, not the context that was current when the thread that runs
# the job was created.
class ActiveJobTest < ActionDispatch::IntegrationTest
  class << self
    attr_accessor :thread_contexts
  end

  setup do
    @previous_adapter = ActiveJob::Base.queue_adapter
    @adapter = ActiveJob::QueueAdapters::AsyncAdapter.new
    ActiveJob::Base.queue_adapter = @adapter

    QueryJob::RESULTS.clear
  end

  teardown do
    @adapter.shutdown
    ActiveJob::Base.queue_adapter = @previous_adapter
  end

  def enqueue(user_agent:, token: "abc123", wait: nil)
    post "/jobs",
      params: {token: token, wait: wait}.compact,
      headers: {"User-Agent" => user_agent}

    assert_response :accepted
  end

  def next_result
    Timeout.timeout(5) { QueryJob::RESULTS.pop }
  end

  # Runs a block directly on a pool thread, without the wrapper of the job,
  # and reads the context of the thread itself.
  def pool_thread_context
    executor = @adapter.instance_variable_get(:@scheduler).instance_variable_get(:@async_executor)
    seen = Queue.new

    sleep 0.3 # Let the thread go idle, so that the same thread is reused.

    executor.post { seen << Aikido::Zen.current_context }

    Timeout.timeout(5) { seen.pop }
  end

  def contexts_of_created_threads
    ActiveJobTest.thread_contexts = Concurrent::Array.new
    yield
    ActiveJobTest.thread_contexts.to_a
  ensure
    ActiveJobTest.thread_contexts = nil
  end

  test "a job runs with the context of the request that enqueued it" do
    enqueue(user_agent: "request-a")

    context, _ = next_result

    assert_equal "request-a", context.request.user_agent
  end

  test "a job runs with the context of the request that enqueued it, not that of the request that created its thread" do
    enqueue(user_agent: "request-a")
    next_result

    enqueue(user_agent: "request-b")

    context, _ = next_result

    assert_equal "request-b", context.request.user_agent
  end

  test "a job runs with the context of the request that enqueued it when its thread was created with no context" do
    QueryJob.perform_later("abc123")
    context, _ = next_result

    assert_nil context

    enqueue(user_agent: "request-b")

    context, _ = next_result

    assert_equal "request-b", context.request.user_agent
  end

  test "a job enqueued outside a request runs with no context" do
    QueryJob.perform_later("abc123")

    context, _ = next_result

    assert_nil context
  end

  test "a delayed job runs with the context of the request that enqueued it" do
    enqueue(user_agent: "request-a", wait: 0.1)

    context, _ = next_result

    assert_equal "request-a", context.request.user_agent
  end

  test "a delayed job runs with the context of the request that enqueued it, not that of the request that created its thread" do
    enqueue(user_agent: "request-a")
    next_result

    enqueue(user_agent: "request-b", wait: 0.2)

    context, _ = next_result

    assert_equal "request-b", context.request.user_agent
  end

  test "a delayed job runs with the context of the request that enqueued it, not that of the request that created the timer thread" do
    enqueue(user_agent: "request-a", wait: 0.1)
    next_result

    enqueue(user_agent: "request-b", wait: 0.1)

    context, _ = next_result

    assert_equal "request-b", context.request.user_agent
  end

  test "a delayed job runs with the context of the request that enqueued it when its thread was created with no context" do
    QueryJob.set(wait: 0.1).perform_later("abc123")
    context, _ = next_result

    assert_nil context

    enqueue(user_agent: "request-b", wait: 0.1)

    context, _ = next_result

    assert_equal "request-b", context.request.user_agent
  end

  test "a delayed job enqueued outside a request runs with no context" do
    QueryJob.set(wait: 0.1).perform_later("abc123")

    context, _ = next_result

    assert_nil context
  end

  test "enqueueing a job in a request creates its threads with no context" do
    contexts = contexts_of_created_threads do
      enqueue(user_agent: "request-a")
      next_result
    end

    refute_empty contexts
    assert_equal [nil], contexts.uniq
  end

  test "enqueueing a delayed job in a request creates its threads with no context" do
    contexts = contexts_of_created_threads do
      enqueue(user_agent: "request-a", wait: 0.1)
      next_result
    end

    refute_empty contexts
    assert_equal [nil], contexts.uniq
  end

  test "a pool thread created by a request has no context once its job is done" do
    enqueue(user_agent: "request-a")
    next_result

    assert_nil pool_thread_context
  end

  test "a reused pool thread has no context after running a job of another request" do
    enqueue(user_agent: "request-a")
    next_result
    enqueue(user_agent: "request-b")
    next_result

    assert_nil pool_thread_context
  end

  test "does not detect SQL injection inside a job enqueued by a request with a harmless token" do
    enqueue(user_agent: "request-a")

    _, error = next_result

    assert_nil error
  end

  test "detects SQL injection inside a job enqueued by a request" do
    enqueue(user_agent: "request-a", token: "' OR 1=1--")

    _, error = next_result

    assert [error, error&.cause].compact.any? { |err| err.is_a?(Aikido::Zen::UnderAttackError) }, error.inspect
  end

  test "detects SQL injection inside a job enqueued by a request when its thread was created by another request" do
    enqueue(user_agent: "request-a")
    next_result

    enqueue(user_agent: "request-b", token: "' OR 1=1--")

    _, error = next_result

    assert [error, error&.cause].compact.any? { |err| err.is_a?(Aikido::Zen::UnderAttackError) }, error.inspect
  end

  test "detects SQL injection inside a delayed job enqueued by a request" do
    enqueue(user_agent: "request-a", token: "' OR 1=1--", wait: 0.1)

    _, error = next_result

    assert [error, error&.cause].compact.any? { |err| err.is_a?(Aikido::Zen::UnderAttackError) }, error.inspect
  end

  test "detects SQL injection inside a delayed job enqueued by a request when its thread was created by another request" do
    enqueue(user_agent: "request-a")
    next_result

    enqueue(user_agent: "request-b", token: "' OR 1=1--", wait: 0.1)

    _, error = next_result

    assert [error, error&.cause].compact.any? { |err| err.is_a?(Aikido::Zen::UnderAttackError) }, error.inspect
  end
end
