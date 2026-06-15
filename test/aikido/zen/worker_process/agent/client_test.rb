# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::WorkerProcess::Agent::ClientTest < ActiveSupport::TestCase
  include WorkerHelpers

  class MockRPCClient
    attr_reader :started, :stopped, :closed, :invoke_results

    def initialize
      @started = false
      @stopped = false
      @closed = false
      @invoke_results = {}
    end

    def start
      @started = true
    end

    def stop
      @stopped = true
    end

    def close
      @closed = true
    end

    def invoke(name, *args, timeout: nil)
      @invoke_results[name]
    end
  end

  def build_agent(invoke_results = {})
    client = MockRPCClient.new
    client.invoke_results.merge!(invoke_results)

    Aikido::Zen::RPC::Client.stub(:new, client) do
      collector = Minitest::Mock.new
      worker = MockWorker.new

      agent = Aikido::Zen::WorkerProcess::Agent::Client.new(
        "127.0.0.1",
        12345,
        config: Aikido::Zen.config,
        worker: worker,
        collector: collector,
        polling_interval: 10,
        heartbeat_interval: 10
      )
      agent.start

      yield agent, worker, collector, client
    end
  end

  test "no tasks are scheduled before #start" do
    client = MockRPCClient.new
    Aikido::Zen::RPC::Client.stub(:new, client) do
      worker = MockWorker.new
      Aikido::Zen::WorkerProcess::Agent::Client.new("127.0.0.1", 12345, worker: worker)
      assert_empty worker.jobs
    end
  end

  test "#close does not stop the RPC client or shutdown the worker" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      agent.close

      assert client.closed
      refute client.stopped
      assert worker.jobs.all?(&:running?)
    end
  end

  test "#start connects the RPC client and schedules three tasks" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      assert client.started
      assert_equal 3, worker.jobs.size
    end
  end

  test "#start handles nil settings from parent gracefully" do
    build_agent("updated_settings" => nil) do |agent|
      pass
    end
  end

  test "#start applies initial settings from parent" do
    config_data = {"configUpdatedAt" => 0, "heartbeatIntervalInMS" => 60_000,
                   "endpoints" => [], "blockedUserIds" => [], "allowedIPAddresses" => [],
                   "receivedAnyStats" => false, "block" => false,
                   "blockNewOutgoingRequests" => false, "domains" => {},
                   "excludedUserIdsFromRateLimiting" => []}
    firewall_data = {"blockedUserAgents" => nil, "monitoredUserAgents" => nil,
                     "userAgentDetails" => [], "blockedIPAddresses" => [],
                     "allowedIPAddresses" => [], "monitoredIPAddresses" => []}

    build_agent("updated_settings" => {"config" => config_data, "firewall_lists" => firewall_data}) do
      assert_equal 60, Aikido::Zen.runtime_settings.heartbeat_interval
    end
  end

  test "#start logs an error when the RPC call raises" do
    client = MockRPCClient.new

    client.stub(:invoke, ->(*) { raise "boom" }) do
      Aikido::Zen::RPC::Client.stub(:new, client) do
        worker = MockWorker.new
        agent = Aikido::Zen::WorkerProcess::Agent::Client.new("127.0.0.1", 12345, worker: worker)

        agent.start

        assert_logged :error, /failed to get initial settings from parent: boom/
      end
    end
  end

  test "#stop does stop the RPC client and does shut down the worker" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      agent.stop

      assert client.stopped
      assert worker.jobs.none?(&:running?)
    end
  end

  test "#send_collector_events flushes the collector and sends events to the parent" do
    events = Array.new(3) { Aikido::Zen::Collector::Events::TrackRequest.new }

    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      collector.expect(:flush_events, events)
      agent.send_collector_events

      assert_mock collector
    end
  end

  test "#send_collector_events logs an error when the RPC call raises" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      collector.expect(:flush_events, [])

      client.stub(:invoke, ->(*) { raise "boom" }) do
        agent.send_collector_events

        assert_logged :error, /failed to send collector events to parent: boom/
      end
    end
  end

  MockRequest = Struct.new(:route, :client_ip, :actor)

  test "#calculate_rate_limits returns nil when the parent returns no result" do
    build_agent("updated_settings" => {}, "calculate_rate_limits" => nil) do |agent|
      request = MockRequest.new(
        Aikido::Zen::Route.new(verb: "GET", path: "/test"),
        "1.2.3.4",
        nil
      )

      assert_nil agent.calculate_rate_limits(request)
    end
  end

  test "#calculate_rate_limits serializes the actor when one is present" do
    build_agent("updated_settings" => {}, "calculate_rate_limits" => nil) do |agent|
      request = MockRequest.new(
        Aikido::Zen::Route.new(verb: "GET", path: "/test"),
        "1.2.3.4",
        Aikido::Zen::Actor.new(id: "user-1", name: "Alice")
      )

      assert_nil agent.calculate_rate_limits(request)
    end
  end

  test "#calculate_rate_limits returns nil and logs when the RPC call raises" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      request = MockRequest.new(
        Aikido::Zen::Route.new(verb: "GET", path: "/test"),
        "1.2.3.4",
        nil
      )

      client.stub(:invoke, ->(*) { raise "RPC error" }) do
        assert_nil agent.calculate_rate_limits(request)
        assert_logged :error, /failed to get rate limits from parent/i
      end
    end
  end

  test "#calculate_rate_limits parses the result returned by the parent" do
    result_data = {
      "throttled" => false,
      "discriminator" => "1.2.3.4",
      "current_requests" => 1,
      "max_requests" => 100,
      "time_remaining" => 60
    }

    build_agent("updated_settings" => {}, "calculate_rate_limits" => result_data) do |agent|
      request = MockRequest.new(
        Aikido::Zen::Route.new(verb: "GET", path: "/test"),
        "1.2.3.4",
        nil
      )

      result = agent.calculate_rate_limits(request)

      assert_instance_of Aikido::Zen::RateLimiter::Result, result
      refute result.throttled?
      assert_equal "1.2.3.4", result.discriminator
    end
  end

  test "the scheduled keepalive task pings the parent" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      assert_nothing_raised { worker.jobs[0].task.call }
    end
  end

  test "the scheduled keepalive task logs an error when the RPC call raises" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      client.stub(:invoke, ->(*) { raise "boom" }) do
        worker.jobs[0].task.call

        assert_logged :error, /keepalive failed: boom/
      end
    end
  end

  test "the scheduled polling task updates settings from the parent" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      assert_nothing_raised { worker.jobs[1].task.call }
    end
  end

  test "the scheduled polling task logs an error when the RPC call raises" do
    build_agent("updated_settings" => {}) do |agent, worker, collector, client|
      client.stub(:invoke, ->(*) { raise "boom" }) do
        worker.jobs[1].task.call

        assert_logged :error, /failed to get settings from parent: boom/
      end
    end
  end
end

class Aikido::Zen::WorkerProcess::Agent::ClientIntegrationTest < ActiveSupport::TestCase
  include WorkerHelpers

  setup do
    @server = Aikido::Zen::WorkerProcess::Agent::Server.new
    @server.start
  end

  teardown do
    @server.stop if @server.started?
  end

  def in_forked_worker
    reader, writer = IO.pipe

    pid = fork do
      reader.close
      begin
        yield
        writer.write("ok")
      rescue => err
        writer.write("#{err.class}: #{err.message}")
      ensure
        writer.close
        exit!
      end
    end

    writer.close
    result = reader.read
    reader.close
    Process.waitpid(pid)

    assert_equal "ok", result
  end

  def build_client
    Aikido::Zen::WorkerProcess::Agent::Client.new(
      @server.host, @server.port,
      worker: MockWorker.new,
      collector: Aikido::Zen.collector
    )
  end

  MockRequest = Struct.new(:route, :client_ip, :actor)

  test "client receives initial runtime settings from the server on startup" do
    Aikido::Zen.api_cache.runtime_config = {
      "configUpdatedAt" => 0, "heartbeatIntervalInMS" => 90_000,
      "endpoints" => [], "blockedUserIds" => [], "allowedIPAddresses" => [],
      "receivedAnyStats" => false, "block" => false,
      "blockNewOutgoingRequests" => false, "domains" => {},
      "excludedUserIdsFromRateLimiting" => []
    }

    in_forked_worker do
      client = build_client
      client.start

      interval = Aikido::Zen.runtime_settings.heartbeat_interval
      raise "expected heartbeat_interval=90, got #{interval}" unless interval == 90
    end
  end

  test "client flushes collector events to the server" do
    in_forked_worker do
      3.times { Aikido::Zen.collector.track_request }
      client = build_client
      client.start
      client.send_collector_events
    end

    captured = []
    wait_until(timeout: 2) do
      captured.concat(Aikido::Zen.collector.flush_events)
      captured.size >= 3
    end
    assert_equal 3, captured.size, "Log: #{@log_output.string}"
  end

  test "client delegates rate-limit calculation to the server" do
    in_forked_worker do
      client = build_client
      client.start

      result = client.calculate_rate_limits(MockRequest.new(
        Aikido::Zen::Route.new(verb: "GET", path: "/test"),
        "1.2.3.4",
        nil
      ))
      raise "expected nil with no rate limit rules, got #{result.inspect}" unless result.nil?
    end
  end
end
