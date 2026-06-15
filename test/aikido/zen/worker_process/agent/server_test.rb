# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::WorkerProcess::Agent::ServerTest < ActiveSupport::TestCase
  setup do
    @server = Aikido::Zen::WorkerProcess::Agent::Server.new
  end

  teardown do
    @server.stop if @server.started?
  end

  test "#started? returns false before #start is called" do
    refute @server.started?
  end

  test "#started? returns true after #start is called" do
    @server.start

    assert @server.started?
  end

  test "#start marks the server as started and exposes host and port" do
    @server.start

    assert @server.started?
    assert_equal "127.0.0.1", @server.host
    assert_operator @server.port, :>, 0
  end

  test "#stop marks the server as stopped" do
    @server.start
    @server.stop

    refute @server.started?
  end

  test "ping handler returns nil" do
    @server.start
    client = Aikido::Zen::RPC::Client.start(Aikido::Zen.secret, @server.host, @server.port)
    assert_nil client.invoke("ping", 2.0)
  ensure
    client.stop
  end

  test "updated_settings handler returns nil config and firewall_lists when cache is empty" do
    Aikido::Zen.api_cache.runtime_config = nil
    Aikido::Zen.api_cache.runtime_firewall_lists = nil

    @server.start
    client = Aikido::Zen::RPC::Client.start(Aikido::Zen.secret, @server.host, @server.port)

    result = client.invoke("updated_settings", 2.0)

    assert_nil result["config"]
    assert_nil result["firewall_lists"]
  ensure
    client.stop
  end

  test "updated_settings handler returns cached config and firewall_lists" do
    config = {"configUpdatedAt" => 1234567890}
    firewall_lists = {"blockedIPAddresses" => []}

    Aikido::Zen.api_cache.runtime_config = config
    Aikido::Zen.api_cache.runtime_firewall_lists = firewall_lists

    @server.start
    client = Aikido::Zen::RPC::Client.start(Aikido::Zen.secret, @server.host, @server.port)

    result = client.invoke("updated_settings", 2.0)

    assert_equal config, result["config"]
    assert_equal firewall_lists, result["firewall_lists"]
  ensure
    client.stop
  end

  test "#updated_settings returns nil config and firewall_lists when cache is empty" do
    Aikido::Zen.api_cache.runtime_config = nil
    Aikido::Zen.api_cache.runtime_firewall_lists = nil

    settings = @server.updated_settings

    assert_nil settings["config"]
    assert_nil settings["firewall_lists"]
  end

  test "#updated_settings returns cached config and firewall_lists" do
    config = {"configUpdatedAt" => 1234567890}
    firewall_lists = {"blockedIPAddresses" => []}

    Aikido::Zen.api_cache.runtime_config = config
    Aikido::Zen.api_cache.runtime_firewall_lists = firewall_lists

    settings = @server.updated_settings

    assert_equal config, settings["config"]
    assert_equal firewall_lists, settings["firewall_lists"]
  end

  test "send_collector_events handler pushes events into the collector" do
    input_events = Array.new(3) { Aikido::Zen::Collector::Events::TrackRequest.new }
    input_events_data = input_events.map(&:as_json)

    @server.start
    client = Aikido::Zen::RPC::Client.start(Aikido::Zen.secret, @server.host, @server.port)

    assert_nil client.invoke("send_collector_events", 2.0, input_events_data)

    output_events = Aikido::Zen.collector.flush_events

    assert_equal input_events_data, output_events.map(&:as_json)
  ensure
    client.stop
  end

  test "#send_collector_events pushes events into the collector" do
    input_events = Array.new(3) { Aikido::Zen::Collector::Events::TrackRequest.new }
    input_events_data = input_events.map(&:as_json)

    @server.send_collector_events(input_events_data)

    output_events = Aikido::Zen.collector.flush_events
    assert_equal input_events_data, output_events.map(&:as_json)
  end

  test "calculate_rate_limits handler returns nil when rate limiting returns no result" do
    route_data = {"method" => "GET", "path" => "/test"}

    @server.start
    client = Aikido::Zen::RPC::Client.start(Aikido::Zen.secret, @server.host, @server.port)

    result = client.invoke("calculate_rate_limits", 2.0, route_data, "1.2.3.4", nil)

    assert_nil result
  ensure
    client.stop
  end

  test "calculate_rate_limits handler returns the serialized result when rate limiting is enabled" do
    route = Aikido::Zen::Route.new(verb: "GET", path: "/test")

    endpoints = Aikido::Zen.runtime_settings.endpoints.send(:to_h)
    endpoints[route] = Aikido::Zen::RuntimeSettings::ProtectionSettings.from_json(
      "forceProtectionOff" => false,
      "allowedIPAddresses" => [],
      "rateLimiting" => {"enabled" => true, "maxRequests" => 3, "windowSizeInMS" => 5000}
    )

    @server.start
    client = Aikido::Zen::RPC::Client.start(Aikido::Zen.secret, @server.host, @server.port)

    route_data = {"method" => "GET", "path" => "/test"}
    result = client.invoke("calculate_rate_limits", 2.0, route_data, "1.2.3.4", nil)

    refute_nil result
    assert_equal false, result["throttled"]
  ensure
    client.stop
  end

  test "#calculate_rate_limits works without an actor" do
    route_data = {"method" => "GET", "path" => "/test"}

    assert_nil @server.calculate_rate_limits(route_data, "1.2.3.4", nil)
  end

  test "#calculate_rate_limits works with an actor" do
    route_data = {"method" => "GET", "path" => "/test"}
    now_ms = Time.now.to_i * 1000
    actor_data = {"id" => "user1", "name" => "Test User", "firstSeenAt" => now_ms, "lastSeenAt" => now_ms}

    assert_nil @server.calculate_rate_limits(route_data, "1.2.3.4", actor_data)
  end

  test "#calculate_rate_limits passes the deserialized route, ip, and actor to the rate limiter" do
    route_data = {"method" => "GET", "path" => "/test"}
    now_ms = Time.now.to_i * 1000
    actor_data = {"id" => "user1", "name" => "Test User", "firstSeenAt" => now_ms, "lastSeenAt" => now_ms}

    received_request = nil
    capture_request = ->(request) {
      received_request = request
      nil
    }

    Aikido::Zen.rate_limiter.stub(:calculate_rate_limits, capture_request) do
      @server.calculate_rate_limits(route_data, "1.2.3.4", actor_data)
    end

    assert_instance_of Aikido::Zen::Route, received_request.route
    assert_equal "GET", received_request.route.verb
    assert_equal "/test", received_request.route.path
    assert_equal "1.2.3.4", received_request.client_ip
    assert_instance_of Aikido::Zen::Actor, received_request.actor
    assert_equal "user1", received_request.actor.id
  end

  test "#calculate_rate_limits passes nil as the actor to the rate limiter when none is given" do
    route_data = {"method" => "GET", "path" => "/test"}

    received_actor = :not_set
    capture_actor = ->(request) {
      received_actor = request.actor
      nil
    }

    Aikido::Zen.rate_limiter.stub(:calculate_rate_limits, capture_actor) do
      @server.calculate_rate_limits(route_data, "1.2.3.4", nil)
    end

    assert_nil received_actor
  end
end
