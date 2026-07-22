# frozen_string_literal: true

require "test_helper"
require "securerandom"

class Aikido::Zen::StreamTest < ActiveSupport::TestCase
  setup do
    config = Aikido::Zen.config
    config.api_token = "TOKEN"

    @endpoint = "#{config.realtime_endpoint}/api/runtime/stream"

    @api_stream = Aikido::Zen::APIStream.new(
      min_backoff: 0.02,
      max_backoff: 0.08,
      backoff_reset: 0.04,
      open_timeout: 1,
      read_timeout: 1
    )
  end

  teardown do
    @api_stream.stop!
  end

  DEFAULT_SSE_BODY = <<~SSE
    event: config-updated
    data: {"serviceId":1,"configUpdatedAt":1779292466}

    event: config-updated
    data: {"serviceId":1,"configUpdatedAt":1779292467}

    : ping

  SSE

  test "#start! returns false if already running" do
    stub_request(:get, @endpoint)
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert @api_stream.start!
    assert_equal false, @api_stream.start!
  end

  test "#handle raises ArgumentError without a block" do
    assert_raises(ArgumentError) { @api_stream.handle("config-updated") }
  end

  test "it starts and connects" do
    connection = stub_request(:get, @endpoint)
      .with(
        headers: {
          "Authorization" => "TOKEN",
          "Accept" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "X-Agent-Platform" => "ruby",
          "X-Agent-Version" => Aikido::Zen::VERSION
        }
      )
      .to_return(status: 200, body: "", headers: {})

    assert_connects(connection, times: 1)
  end

  test "it handles valid events" do
    connection = stub_request(:get, @endpoint)
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    events = Concurrent::Array.new
    @api_stream.handle("config-updated") { |event| events << event }

    assert_connects(connection, times: 1)

    assert_equal 2, events.size

    assert_equal "config-updated", events[0][:type]
    assert_equal 1, events[0][:data]["serviceId"]
    assert_equal 1779292466, events[0][:data]["configUpdatedAt"]

    assert_equal "config-updated", events[1][:type]
    assert_equal 1, events[1][:data]["serviceId"]
    assert_equal 1779292467, events[1][:data]["configUpdatedAt"]
  end

  test "it skips invalid events and continues processing" do
    body = <<~SSE
      event: config-updated
      data: not valid json

      event: config-updated
      data: {"serviceId":1,"configUpdatedAt":1779292466}

    SSE

    connection = stub_request(:get, @endpoint)
      .to_return(status: 200, body: body)

    events = Concurrent::Array.new
    @api_stream.handle("config-updated") { |event| events << event }

    assert_connects(connection, times: 1)

    assert_equal 1, events.size

    assert_equal "config-updated", events[0][:type]
    assert_equal 1, events[0][:data]["serviceId"]
    assert_equal 1779292466, events[0][:data]["configUpdatedAt"]
  end

  test "it skips handler errors and continues processing" do
    connection = stub_request(:get, @endpoint)
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    events = Concurrent::Array.new
    @api_stream.handle("config-updated") { |_event| raise "handler error" }
    @api_stream.handle("config-updated") { |event| events << event }

    assert_connects(connection, times: 1)

    assert_equal 2, events.size
  end

  test "it reconnects after the stream ends naturally" do
    connection = stub_request(:get, @endpoint)
      .to_return(status: 200, body: DEFAULT_SSE_BODY).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert_connects(connection, times: 2)
  end

  test "it reconnects after connection reset" do
    connection = stub_request(:get, @endpoint)
      .to_raise(Errno::ECONNRESET).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert_connects(connection, times: 2)
  end

  test "it reconnects after connection refused" do
    connection = stub_request(:get, @endpoint)
      .to_raise(Errno::ECONNREFUSED).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert_connects(connection, times: 2)
  end

  test "it reconnects after open timeout" do
    connection = stub_request(:get, @endpoint)
      .to_raise(Net::OpenTimeout).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert_connects(connection, times: 2)
  end

  test "it reconnects after write timeout" do
    connection = stub_request(:get, @endpoint)
      .to_raise(Net::WriteTimeout).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert_connects(connection, times: 2)
  end

  test "it reconnects after read timeout" do
    connection = stub_request(:get, @endpoint)
      .to_raise(Net::ReadTimeout).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert_connects(connection, times: 2)
  end

  test "it reconnects after unexpected error" do
    connection = stub_request(:get, @endpoint)
      .to_raise(RuntimeError).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    assert_connects(connection, times: 2)
  end

  test "it reconnects after unexpected HTTP status code" do
    connection = stub_request(:get, @endpoint)
      .to_return(status: 418).then
      .to_return(status: 200, body: DEFAULT_SSE_BODY)

    @api_stream.start!

    assert @api_stream.running?

    wait_until(timeout: 2) { connected?(connection, times: 2) }

    assert @api_stream.running?

    assert_requested connection, times: 2
  end

  test "it does not reconnect after 401 Unauthorized" do
    connection = stub_request(:get, @endpoint)
      .to_return(status: 401)

    @api_stream.start!

    assert @api_stream.running?

    wait_until(timeout: 2) { connected?(connection, times: 1) }

    refute @api_stream.running?

    assert_requested connection, times: 1
  end

  test "it does not reconnect after 403 Forbidden" do
    connection = stub_request(:get, @endpoint)
      .to_return(status: 403)

    @api_stream.start!

    assert @api_stream.running?

    wait_until(timeout: 2) { connected?(connection, times: 1) }

    refute @api_stream.running?

    assert_requested connection, times: 1
  end

  private

  def connected?(connection, times: 1)
    WebMock::RequestRegistry.instance.times_executed(connection.request_pattern) == times
  end

  def assert_connects(connection, times:, timeout: 2)
    @api_stream.start!

    wait_until(timeout: timeout) { connected?(connection, times: times) }

    @api_stream.stop!

    assert_requested connection, times: times
  end
end
