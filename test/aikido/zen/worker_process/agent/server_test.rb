# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::WorkerProcess::Agent::ServerTest < ActiveSupport::TestCase
  setup do
    @server = Aikido::Zen::WorkerProcess::Agent::Server.new
  end

  teardown do
    @server.stop! if @server.started?
  end

  test "#started? returns false before #start! is called" do
    refute @server.started?
  end

  test "#start! marks the server as started and exposes host and port" do
    @server.start!

    assert @server.started?
    assert_equal "127.0.0.1", @server.host
  end

  test "#stop! marks the server as stopped" do
    @server.start!
    @server.stop!

    refute @server.started?
  end

  test "#send_collector_events pushes events into the collector" do
    input_events = Array.new(3) { Aikido::Zen::Collector::Events::TrackRequest.new }
    input_events_data = input_events.map(&:as_json)

    @server.send_collector_events(input_events_data)

    output_events = Aikido::Zen.collector.flush_events
    assert_equal input_events_data, output_events.map(&:as_json)
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
end
