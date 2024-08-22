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

  class AttackTest < ActiveSupport::TestCase
    test "sets type to detected_attack" do
      attack = TestAttack.new
      event = Aikido::Agent::Events::Attack.new(attack: attack)

      assert_equal "detected_attack", event.type
    end

    test "includes the attack's JSON representation" do
      attack = TestAttack.new(context: stub_context)
      event = Aikido::Agent::Events::Attack.new(attack: attack)

      assert_equal({some: "info"}, event.as_json[:attack])
    end

    test "includes the request's JSON representation" do
      context = stub_context

      attack = TestAttack.new(context: context)
      event = Aikido::Agent::Events::Attack.new(attack: attack)

      assert_equal context.request.as_json, event.as_json[:request]
    end

    def stub_context(**options)
      env = Rack::MockRequest.env_for("/test", **options)
      Aikido::Agent::Context.from_rack_env(env)
    end

    class TestAttack < Aikido::Firewall::Attack
      def initialize(sink: nil, context: nil, operation: "test")
        super
      end

      def log_message
        "test attack"
      end

      def as_json
        {some: "info"}
      end

      def exception(*)
        Aikido::Firewall::UnderAttackError.new(self)
      end
    end
  end

  class HeartbeatTest < ActiveSupport::TestCase
    test "sets type to heartbeat" do
      event = Aikido::Agent::Events::Heartbeat.new(serialized_stats: {})

      assert_equal "heartbeat", event.type
    end

    test "sets the stats to the serialized_stats passed" do
      event = Aikido::Agent::Events::Heartbeat.new(
        serialized_stats: {sinks: {}, requests: {}}
      )

      assert_equal({sinks: {}, requests: {}}, event.as_json[:stats])
    end

    test "includes the outbound hostnames visited by the app" do
      skip "Implement support for outbound request interception"
    end

    test "includes the recognized framework routes" do
      skip "Implement support for routes"
    end

    test "includes the users the developer told us about" do
      skip "Implement support for users"
    end
  end
end
