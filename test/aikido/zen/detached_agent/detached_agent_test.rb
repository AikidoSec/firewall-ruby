# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::DetachedAgent::AgentTest < ActiveSupport::TestCase
  def with_mocks(front_object, on_drb_start)
    DRbObject.stub :new_with_uri, front_object do
      DRb.stub :start_service, on_drb_start do
        detached_agent = Aikido::Zen::DetachedAgent::Agent.new
        yield detached_agent
      end
    end
  end

  test "all track methods are enqueue and later processed by the background worker" do
    front_object = Minitest::Mock.new

    front_object.expect :middleware_installed!, nil

    # This method will be called 3 times later
    track_request_calls = 0
    5.times do
      front_object.expect(:track_request, nil) { track_request_calls += 1 }
    end

    front_object.expect :track_scan, nil do |sink_name, has_errors, duration|
      assert_equal "sink-name", sink_name
      refute has_errors
      assert_equal 100, duration
    end

    front_object.expect :track_route, nil do |route, schema|
      assert_equal "some-route", route
      assert_equal({"key" => "value"}, schema) # as_json converts keys from symbols to strings
    end

    front_object.expect :track_outbound, nil do |outbound|
      assert_equal "some-host", outbound.host
      assert_equal "some-port", outbound.port
    end

    front_object.expect :track_user, nil do |id, name, first_seen_at, ip|
      assert_equal "some-user-id", id
      assert_equal "some-user-name", name
      assert_equal Time.at(17111987), first_seen_at
      assert_equal "some-ip", ip
    end

    front_object.expect :track_attack, nil do |sink_name, is_blocked|
      assert_equal "sink-name", sink_name
      refute is_blocked
    end

    sink_struct = OpenStruct.new(name: "sink-name")

    drb_start_called = false
    on_drb_start = -> { drb_start_called = true }

    with_mocks(front_object, on_drb_start) do |detached_agent|
      detached_agent.track_request
      detached_agent.middleware_installed!
      detached_agent.track_route(OpenStruct.new(route: "some-route", schema: {key: "value"}))
      detached_agent.track_outbound(Aikido::Zen::OutboundConnection.new(host: "some-host", port: "some-port"))
      detached_agent.track_scan(OpenStruct.new(sink: sink_struct, errors?: false, duration: 100))
      detached_agent.track_user(OpenStruct.new(id: "some-user-id", name: "some-user-name", first_seen_at: Time.at(17111987), ip: "some-ip"))
      detached_agent.track_attack(OpenStruct.new(sink: sink_struct, blocked?: false))

      detached_agent.track_request
      detached_agent.track_request

      # Allow the background thread some time to process everything
      sleep 0.1

      # Forks are gracefully handled: we continue processing messages even though the
      # background worker was restarted
      detached_agent.handle_fork

      detached_agent.track_request
      detached_agent.track_request

      sleep 0.1
    end

    assert drb_start_called

    assert_mock front_object
    assert_equal 5, track_request_calls
    front_object.verify # No extra calls to the front_object mock

    # Due to we're protecting ourselves in the BackgroundWorker loop —catching exceptions—,
    # we can swallow down the assertions.
    # With this refure_logged, we ensure that no assertion was omitted.
    refute_logged(/minitest/)
  end
end
