# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::EventTest < ActiveSupport::TestCase
  test "it exposes its type and time" do
    event = Aikido::Agent::Event.new(type: "test", time: Time.at(1234567890))

    assert_equal "test", event.type
    assert_equal Time.at(1234567890), event.time
  end

  test "#time defaults to the current time if not given" do
    freeze_time do
      event = Aikido::Agent::Event.new(type: "test")
      assert_equal Time.now.utc, event.time
    end
  end

  test "it captures the agent information" do
    event = Aikido::Agent::Event.new(type: "test")

    assert_kind_of Aikido::Agent::Info, event.agent_info
    assert_equal "firewall-ruby", event.agent_info.library_name
  end

  test "#as_json includes the type" do
    event = Aikido::Agent::Event.new(type: "test")

    assert_equal "test", event.as_json[:type]
  end

  test "#as_json serializes the time in milliseconds" do
    event = Aikido::Agent::Event.new(type: "test", time: Time.at(123))

    assert_equal 123000, event.as_json[:time]
  end

  test "#as_json serializes the agent info" do
    event = Aikido::Agent::Event.new(type: "test")
    info = Aikido::Agent::Info.new

    refute_nil info.as_json, event.as_json[:agent]
  end

  class StartedTest < ActiveSupport::TestCase
    test "sets type to started" do
      event = Aikido::Agent::Events::Started.new

      assert_equal "started", event.type
    end

    test "allows overriding time" do
      event = Aikido::Agent::Events::Started.new(time: Time.at(1234567890))

      assert_equal Time.at(1234567890), event.time
    end
  end
end
