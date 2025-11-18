# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Collector::EventTests < ActiveSupport::TestCase
  include Aikido::Zen::Collector::Events

  def stub_track_request_event
    TrackRequest.new
  end

  def stub_track_request_event_from_json(data)
    TrackRequest.from_json(data)
  end

  def stub_track_attack_wave_event(being_blocked: false)
    TrackAttackWave.new(being_blocked: being_blocked)
  end

  def stub_track_attack_wave_event_from_json(data)
    TrackAttackWave.from_json(data)
  end

  def stub_track_scan_event
    TrackScan.new("sink_name", 1.0, has_errors: false)
  end

  def stub_track_scan_event_from_json(data)
    TrackScan.from_json(data)
  end

  def stub_track_attack_event
    TrackAttack.new("sink_name", being_blocked: false)
  end

  def stub_track_attack_event_from_json(data)
    TrackAttack.from_json(data)
  end

  def stub_actor
    Aikido::Zen::Actor.new(
      id: "0",
      name: "user",
      ip: "1.2.3.4",
      first_seen_at: Time.utc(2024, 9, 1, 16, 20, 42)
    )
  end

  def stub_track_user_event
    actor = stub_actor
    TrackUser.new(actor)
  end

  def stub_track_user_event_from_json(data)
    TrackUser.from_json(data)
  end

  def stub_outbound_connection
    Aikido::Zen::OutboundConnection.new(
      host: "localhost",
      port: "80"
    )
  end

  def stub_track_outbound_event
    outbound_connection = stub_outbound_connection
    TrackOutbound.new(outbound_connection)
  end

  def stub_track_outbound_event_from_json(data)
    TrackOutbound.from_json(data)
  end

  def stub_route
    Aikido::Zen::Route.new(verb: "GET", path: "/")
  end

  def stub_schema
    Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: Aikido::Zen::Request::Schema::EMPTY_SCHEMA,
      query_schema: Aikido::Zen::Request::Schema::EMPTY_SCHEMA,
      auth_schema: Aikido::Zen::Request::Schema::AuthSchemas::NONE
    )
  end

  def stub_track_route_event
    route = stub_route
    schema = stub_schema
    TrackRoute.new(route, schema)
  end

  def stub_track_route_event_from_json(data)
    TrackRoute.from_json(data)
  end

  def stub_event_from_json(data)
    Aikido::Zen::Collector::Event.from_json(data)
  end

  test "create new track request event" do
    assert_silent { stub_track_request_event }
  end

  test "serialize track request event as JSON" do
    event = stub_track_request_event

    assert_hash_subset_of event.as_json, {
      type: "track_request"
    }
  end

  test "deserialize track request event from JSON" do
    event = stub_track_request_event
    event_hash = event.as_json

    other = stub_track_request_event_from_json(event_hash)

    assert_equal event_hash, other.as_json
  end

  test "deserialize event for track request from JSON" do
    event = stub_track_request_event

    other = stub_event_from_json(event.as_json)

    assert_equal TrackRequest, other.class
  end

  test "track request handle calls handle_track_request" do
    event = stub_track_request_event

    collector = Minitest::Mock.new
    collector.expect :handle_track_request, nil, []

    event.handle(collector)

    assert_mock collector
  end

  test "create new track attack wave event" do
    assert_silent { stub_track_attack_wave_event }
  end

  test "serialize track attack wave event as JSON" do
    event = stub_track_attack_wave_event

    assert_hash_subset_of event.as_json, {
      type: "track_attack_wave"
    }
  end

  test "deserialize track attack wave event from JSON" do
    event = stub_track_attack_wave_event
    event_hash = event.as_json

    other = stub_track_attack_wave_event_from_json(event_hash)

    assert_equal event_hash, other.as_json
  end

  test "deserialize event for track attack wave from JSON" do
    event = stub_track_attack_wave_event

    other = stub_event_from_json(event.as_json)

    assert_equal TrackAttackWave, other.class
  end

  test "track attack wave handle calls handle_track_attack_wave" do
    event = stub_track_attack_wave_event

    collector = Minitest::Mock.new
    collector.expect(:handle_track_attack_wave, nil, being_blocked: false)

    event.handle(collector)

    assert_mock collector
  end

  test "create new track scan event" do
    assert_silent { stub_track_scan_event }
  end

  test "serialize track scan event as JSON" do
    event = stub_track_scan_event

    assert_hash_subset_of event.as_json, {
      type: "track_scan",
      sink_name: "sink_name",
      duration: 1.0,
      has_errors: false
    }
  end

  test "deserialize track scan event from JSON" do
    event = stub_track_scan_event
    event_hash = event.as_json

    other = stub_track_scan_event_from_json(event_hash)

    assert_equal event_hash, other.as_json
  end

  test "deserialize event for track scan from JSON" do
    event = stub_track_scan_event

    other = stub_event_from_json(event.as_json)

    assert_equal TrackScan, other.class
  end

  test "track scan handle calls handle_track_scan" do
    event = stub_track_scan_event

    collector = Minitest::Mock.new
    collector.expect(:handle_track_scan, nil, ["sink_name", 1.0], has_errors: false)

    event.handle(collector)

    assert_mock collector
  end

  test "create new track attack event" do
    assert_silent { stub_track_attack_event }
  end

  test "serialize track attack event as JSON" do
    event = stub_track_attack_event

    assert_hash_subset_of event.as_json, {
      type: "track_attack",
      sink_name: "sink_name",
      being_blocked: false
    }
  end

  test "deserialize track attack event from JSON" do
    event = stub_track_attack_event
    event_hash = event.as_json

    other = stub_track_attack_event_from_json(event_hash)

    assert_equal event_hash, other.as_json
  end

  test "deserialize event for track attack from JSON" do
    event = stub_track_attack_event

    other = stub_event_from_json(event.as_json)

    assert_equal TrackAttack, other.class
  end
  test "track attack handle calls handle_track_attack" do
    event = stub_track_attack_event

    collector = Minitest::Mock.new
    collector.expect(:handle_track_attack, nil, ["sink_name"], being_blocked: false)

    event.handle(collector)

    assert_mock collector
  end

  test "create new track user event" do
    assert_silent { stub_track_user_event }
  end

  test "serialize track user event as JSON" do
    event = stub_track_user_event
    event_hash = event.as_json

    assert_hash_subset_of event_hash, {
      type: "track_user",
      actor: stub_actor.as_json
    }
  end

  test "deserialize track user event from JSON" do
    event = stub_track_user_event
    event_hash = event.as_json

    other = stub_track_user_event_from_json(event_hash)

    assert_equal event_hash, other.as_json
  end

  test "deserialize event for track user from JSON" do
    event = stub_track_user_event

    other = stub_event_from_json(event.as_json)

    assert_equal TrackUser, other.class
  end

  test "track user handle calls handle_track_user" do
    event = stub_track_user_event

    collector = Minitest::Mock.new
    collector.expect(:handle_track_user, nil) do |actor|
      actor.is_a?(Aikido::Zen::Actor)
    end

    event.handle(collector)

    assert_mock collector
  end

  test "create new track outbound event" do
    assert_silent { stub_track_outbound_event }
  end

  test "serialize track outbound event as JSON" do
    event = stub_track_outbound_event
    event_hash = event.as_json

    assert_hash_subset_of event_hash, {
      type: "track_outbound",
      connection: stub_outbound_connection.as_json
    }
  end

  test "deserialize track outbound event from JSON" do
    event = stub_track_outbound_event
    event_hash = event.as_json

    other = stub_track_outbound_event_from_json(event_hash)

    assert_equal event_hash, other.as_json
  end

  test "deserialize event for track outbound from JSON" do
    event = stub_track_outbound_event

    other = stub_event_from_json(event.as_json)

    assert_equal TrackOutbound, other.class
  end

  test "track outbound handle calls handle_track_outbound" do
    event = stub_track_outbound_event

    collector = Minitest::Mock.new
    collector.expect(:handle_track_outbound, nil) do |connection|
      connection.is_a?(Aikido::Zen::OutboundConnection)
    end

    event.handle(collector)

    assert_mock collector
  end

  test "create new track route event" do
    assert_silent { stub_track_route_event }
  end

  test "serialize track route event as JSON" do
    event = stub_track_route_event
    event_hash = event.as_json

    assert_hash_subset_of event_hash, {
      type: "track_route",
      route: stub_route.as_json,
      schema: stub_schema.as_json
    }
  end

  test "deserialize track route event from JSON" do
    event = stub_track_route_event
    event_hash = event.as_json

    other = stub_track_route_event_from_json(event_hash)

    assert_equal event_hash, other.as_json
  end

  test "deserialize event for track route from JSON" do
    event = stub_track_route_event

    other = stub_event_from_json(event.as_json)

    assert_equal TrackRoute, other.class
  end

  test "track route handle calls handle_track_route" do
    event = stub_track_route_event

    collector = Minitest::Mock.new
    collector.expect(:handle_track_route, nil) do |route, schema|
      route.is_a?(Aikido::Zen::Route) && schema.is_a?(Aikido::Zen::Request::Schema)
    end

    event.handle(collector)

    assert_mock collector
  end
end
