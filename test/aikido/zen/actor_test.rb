# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::ActorTest < ActiveSupport::TestCase
  include StubsCurrentContext

  class CastingTest < ActiveSupport::TestCase
    AdminUser = Struct.new(:id) do
      def to_aikido_actor
        Aikido::Zen::Actor.new(id: "admin:#{id}")
      end
    end

    test "returns nil if given nil" do
      assert_nil Aikido::Zen::Actor(nil)
    end

    test "returns the same object if given an Actor" do
      actor = Aikido::Zen::Actor.new(id: 123, name: "Jane Doe")
      assert_same actor, Aikido::Zen::Actor(actor)
    end

    test "returns the return value of #to_aikido_actor if implemented" do
      admin = AdminUser.new(456)

      actor = Aikido::Zen::Actor(admin)
      assert_equal admin.to_aikido_actor, actor
      assert_kind_of Aikido::Zen::Actor, actor
      assert_equal "admin:456", actor.id
      assert_nil actor.name
    end

    test "extracts :id and :name if given a Hash" do
      data = {id: 123, name: "Jane Doe"}

      actor = Aikido::Zen::Actor(data)
      assert_kind_of Aikido::Zen::Actor, actor
      assert_equal "123", actor.id
      assert_equal "Jane Doe", actor.name
    end

    test "accepts string keys if given a Hash" do
      data = {"id" => 123, "name" => "Jane Doe"}

      actor = Aikido::Zen::Actor(data)
      assert_kind_of Aikido::Zen::Actor, actor
      assert_equal "123", actor.id
      assert_equal "Jane Doe", actor.name
    end

    test "returns nil if given an incompatible object" do
      assert_nil Aikido::Zen::Actor(Object.new)
    end

    test "returns nil if given a hash with a nil id" do
      assert_nil Aikido::Zen::Actor(id: nil)
    end

    test "returns nil if given a hash with an empty id" do
      assert_nil Aikido::Zen::Actor(id: "")
    end

    test "returns nil if given a hash with a blank id" do
      assert_nil Aikido::Zen::Actor(id: " ")
    end
  end

  test "id is the only required attribute" do
    freeze_time do
      actor = Aikido::Zen::Actor.new(id: "test")

      assert_equal "test", actor.id
      assert_nil actor.name
      assert_nil actor.ip
      assert_equal Time.now.utc, actor.first_seen_at
      assert_equal Time.now.utc, actor.last_seen_at
    end
  end

  test "ip defaults to the current context's request" do
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(env)

    actor = Aikido::Zen::Actor.new(id: "test")
    assert_equal "1.2.3.4", actor.ip
  end

  test "#to_aikido_actor returns the same instance" do
    actor = Aikido::Zen::Actor.new(id: "test")
    assert_same actor, actor.to_aikido_actor
  end

  test "#update sets the #last_seen_at but does not change #first_seen_at" do
    first_seen = Time.utc(2024, 9, 1, 16, 20, 42)

    actor = Aikido::Zen::Actor.new(id: "test", seen_at: first_seen)
    assert_equal first_seen, actor.first_seen_at
    assert_equal first_seen, actor.last_seen_at

    actor.update(seen_at: first_seen + 20)
    assert_equal first_seen, actor.first_seen_at
    assert_equal first_seen + 20, actor.last_seen_at
  end

  test "#update does not override #last_seen_at if given an older timestamp" do
    timestamp = Time.utc(2024, 9, 1, 16, 20, 42)

    actor = Aikido::Zen::Actor.new(id: "test", seen_at: timestamp)

    assert_no_changes "actor.last_seen_at" do
      actor.update(seen_at: timestamp - 1)
    end
  end

  test "#update changes the #last_seen_at to the current time by default" do
    freeze_time do
      actor = Aikido::Zen::Actor.new(id: "test", seen_at: Time.now.utc - 20)

      assert_changes "actor.last_seen_at", to: actor.first_seen_at + 20 do
        actor.update
      end
    end
  end

  test "#update changes the actor's #ip if given a different value" do
    actor = Aikido::Zen::Actor.new(id: "test", ip: "10.0.0.1")

    assert_changes "actor.ip", to: "1.2.3.4" do
      actor.update(ip: "1.2.3.4")
    end
  end

  test "#update does not change the #ip if given a nil value" do
    actor = Aikido::Zen::Actor.new(id: "test", ip: "10.0.0.1")

    assert_no_changes "actor.ip" do
      actor.update(ip: nil)
    end
  end

  test "#update sets the #ip from the current request if present" do
    actor = Aikido::Zen::Actor.new(id: "test", ip: "10.0.0.1")

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(env)

    assert_changes "actor.ip", to: "1.2.3.4" do
      actor.update
    end
  end

  test "#as_json includes the expected attributes" do
    actor = Aikido::Zen::Actor.new(
      id: "123",
      name: "Jane Doe",
      ip: "1.2.3.4",
      seen_at: Time.at(1234567890)
    )
    actor.update(seen_at: Time.at(1234577890))

    expected = {
      id: "123",
      name: "Jane Doe",
      lastIpAddress: "1.2.3.4",
      firstSeenAt: 1234567890000,
      lastSeenAt: 1234577890000
    }

    assert_equal expected, actor.as_json
  end
end
