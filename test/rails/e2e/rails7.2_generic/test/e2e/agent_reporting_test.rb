# frozen_string_literal: true

require "test_helper"

class AgentReportingTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  include MockServerHelpers

  test "sends a started event when the app boots" do
    # The started event is sent asynchronously shortly after the server boots,
    # before any test request is made.
    events = wait_for_event(type: "started", timeout: 15)

    assert_not_empty events

    event = events.first

    assert_not_nil event["time"]
    assert_not_nil event.dig("agent", "version")
    assert_equal "firewall-ruby", event.dig("agent", "library")
  end
end
