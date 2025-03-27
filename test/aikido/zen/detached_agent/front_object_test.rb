# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::DetachedAgent::FrontObjectTest < ActiveSupport::TestCase
  setup do
    @config = Aikido::Zen::Config.new
    @collector = Minitest::Mock.new(Aikido::Zen::Collector.new(config: @config))
    @front_object = Aikido::Zen::DetachedAgent::FrontObject.new(config: @config, collector: @collector)
  end

  test "middleware_installed is forwarded" do
    @collector.expect :middleware_installed!, nil
    @front_object.middleware_installed!
    assert_mock @collector
  end

  test "track_request is forwarded" do
    @collector.expect :track_request, nil
    @front_object.track_request
    assert_mock @collector
  end

  test "track_outbound is forwarded" do
    outbound_obj = Aikido::Zen::OutboundConnection.new(host: "some-host", port: "some-port")
    @collector.expect :track_outbound, nil, [outbound_obj]
    # duplicate the object to ensure it has the same shape, but it's not the same-same object
    @front_object.track_outbound(outbound_obj.dup)
    assert_mock @collector
  end

  test "track_scan is forwarded" do
    @collector.expect(:track_scan, nil) do |scan|
      assert scan.is_a?(Struct) # It's the kind-of Struct and not the actual Scan object
      assert scan.sink.is_a?(Struct) # It's the kind-of Struct and not the actual Sink object
      assert_equal "some-sink-name", scan.sink.name
      assert_equal false, scan.errors?
      assert_equal scan.duration, 100.0
    end

    @front_object.track_scan("some-sink-name", false, 100.0)
    assert_mock @collector
  end

  test "track_user is forwarded" do
    @collector.expect(:track_user, nil) do |actor|
      # Actor uses only id and name to check equality
      assert_equal Aikido::Zen::Actor.new(id: "some-id", name: "some-name"), actor
      assert_equal actor.ip, "1.1.3.4"
      assert_equal actor.last_seen_at, Time.at(17111987)
    end

    @front_object.track_user("some-id", "some-name", Time.at(17111987), "1.1.3.4")
    assert_mock @collector
  end

  test "track_attack is forwarded" do
    @collector.expect(:track_attack, nil) do |attack|
      assert attack.is_a?(Struct) # It's the kind-of Struct and not the actual Scan object
      assert attack.sink.is_a?(Struct) # It's the kind-of Struct and not the actual Sink object

      assert_equal "some-sink-name", attack.sink.name
      refute attack.blocked?
    end

    @front_object.track_attack "some-sink-name", false
    assert_mock @collector
  end

  test "track_route is forwarded" do
    @collector.expect(:track_route, nil) do |request|
      assert request.is_a?(Struct) # It's the kind-of Struct and not the actual Request object

      assert_equal "some-route", request.route
      assert_equal request.schema.as_json, Aikido::Zen::Request::Schema.new(
        content_type: nil,
        body_schema: Aikido::Zen::Request::Schema::EMPTY_SCHEMA,
        query_schema: Aikido::Zen::Request::Schema::EMPTY_SCHEMA,
        auth_schema: Aikido::Zen::Request::Schema::AuthSchemas.new([])
      ).as_json
    end

    @front_object.track_route "some-route", {} # it receives a hash object as schema
    assert_mock @collector
  end
end
