# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::ActorTest < ActiveSupport::TestCase
  include StubsCurrentContext

  class CastingTest < ActiveSupport::TestCase
    User = Struct.new(:id, :name, :email) do
      def to_model
        self
      end
    end

    NamelessModel = Struct.new(:id) do
      def to_model
        self
      end
    end

    AdminUser = Struct.new(:id) do
      def to_model
        self
      end

      def to_aikido_actor
        Aikido::Agent::Actor.new(id: "admin:#{id}")
      end
    end

    test "returns nil if given nil" do
      assert_nil Aikido::Agent::Actor(nil)
    end

    test "returns the same object if given an Actor" do
      actor = Aikido::Agent::Actor.new(id: 123, name: "Jane Doe")
      assert_same actor, Aikido::Agent::Actor(actor)
    end

    test "returns the return value of #to_aikido_actor if implemented" do
      admin = AdminUser.new(456)

      actor = Aikido::Agent::Actor(admin)
      assert_equal admin.to_aikido_actor, actor
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "admin:456", actor.id
      assert_nil actor.name
    end

    test "extracts the #id and #name attributes from objects that implement #to_model" do
      user = User.new(234, "Jane Doe", "jane@example.com")

      actor = Aikido::Agent::Actor(user)
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "234", actor.id
      assert_equal "Jane Doe", actor.name
    end

    test "ignores the name if the model does not implement #name" do
      model = NamelessModel.new(567)

      actor = Aikido::Agent::Actor(model)
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "567", actor.id
      assert_nil actor.name
    end

    test "extracts the attributes mapped in the config from objects that implement #to_model" do
      Aikido::Agent.config.user_attribute_mappings.update(name: :email)

      user = User.new(234, "Jane Doe", "jane@example.com")

      actor = Aikido::Agent::Actor(user)
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "234", actor.id
      assert_equal "jane@example.com", actor.name
    end

    test "ignores the name if the model does not implement the configured attribute" do
      Aikido::Agent.config.user_attribute_mappings.update(name: :full_name)

      model = NamelessModel.new(567)

      actor = Aikido::Agent::Actor(model)
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "567", actor.id
      assert_nil actor.name
    end

    test "extracts :id and :name if given a Hash" do
      data = {id: 123, name: "Jane Doe"}

      actor = Aikido::Agent::Actor(data)
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "123", actor.id
      assert_equal "Jane Doe", actor.name
    end

    test "accepts string keys if given a Hash" do
      data = {"id" => 123, "name" => "Jane Doe"}

      actor = Aikido::Agent::Actor(data)
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "123", actor.id
      assert_equal "Jane Doe", actor.name
    end

    test "disregards attribute mappings when given a Hash" do
      Aikido::Agent.config.user_attribute_mappings.update(name: :full_name)

      data = {id: 123, name: "Jane", full_name: "Jane Doe"}

      actor = Aikido::Agent::Actor(data)
      assert_kind_of Aikido::Agent::Actor, actor
      assert_equal "123", actor.id
      assert_equal "Jane", actor.name
    end

    test "returns nil if given an incompatible object" do
      assert_nil Aikido::Agent::Actor(Object.new)
    end

    test "returns nil if given an object with a nil id" do
      user = User.new(nil, "Jane Doe", "jane@example.com")
      assert_nil Aikido::Agent::Actor(user)
    end

    test "returns nil if given an object with an empty id" do
      user = User.new("", "Jane Doe", "jane@example.com")
      assert_nil Aikido::Agent::Actor(user)
    end

    test "returns nil if given an object with a blank id" do
      user = User.new(" ", "Jane Doe", "jane@example.com")
      assert_nil Aikido::Agent::Actor(user)
    end
  end

  test "id is the only required attribute" do
    freeze_time do
      actor = Aikido::Agent::Actor.new(id: "test")

      assert_equal "test", actor.id
      assert_nil actor.name
      assert_nil actor.ip
      assert_equal Time.now.utc, actor.first_seen_at
      assert_equal Time.now.utc, actor.last_seen_at
    end
  end

  test "ip defaults to the current context's request" do
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    Aikido::Agent.current_context = Aikido::Agent::Context.from_rack_env(env)

    actor = Aikido::Agent::Actor.new(id: "test")
    assert_equal "1.2.3.4", actor.ip
  end

  test "#to_aikido_actor returns the same instance" do
    actor = Aikido::Agent::Actor.new(id: "test")
    assert_same actor, actor.to_aikido_actor
  end

  test "#update sets the #last_seen_at but does not change #first_seen_at" do
    first_seen = Time.utc(2024, 9, 1, 16, 20, 42)

    actor = Aikido::Agent::Actor.new(id: "test", seen_at: first_seen)
    assert_equal first_seen, actor.first_seen_at
    assert_equal first_seen, actor.last_seen_at

    actor.update(seen_at: first_seen + 20)
    assert_equal first_seen, actor.first_seen_at
    assert_equal first_seen + 20, actor.last_seen_at
  end

  test "#update does not override #last_seen_at if given an older timestamp" do
    timestamp = Time.utc(2024, 9, 1, 16, 20, 42)

    actor = Aikido::Agent::Actor.new(id: "test", seen_at: timestamp)

    assert_no_changes "actor.last_seen_at" do
      actor.update(seen_at: timestamp - 1)
    end
  end

  test "#update changes the #last_seen_at to the current time by default" do
    freeze_time do
      actor = Aikido::Agent::Actor.new(id: "test", seen_at: Time.now.utc - 20)

      assert_changes "actor.last_seen_at", to: actor.first_seen_at + 20 do
        actor.update
      end
    end
  end

  test "#update changes the actor's #ip if given a different value" do
    actor = Aikido::Agent::Actor.new(id: "test", ip: "10.0.0.1")

    assert_changes "actor.ip", to: "1.2.3.4" do
      actor.update(ip: "1.2.3.4")
    end
  end

  test "#update does not change the #ip if given a nil value" do
    actor = Aikido::Agent::Actor.new(id: "test", ip: "10.0.0.1")

    assert_no_changes "actor.ip" do
      actor.update(ip: nil)
    end
  end

  test "#update sets the #ip from the current request if present" do
    actor = Aikido::Agent::Actor.new(id: "test", ip: "10.0.0.1")

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    Aikido::Agent.current_context = Aikido::Agent::Context.from_rack_env(env)

    assert_changes "actor.ip", to: "1.2.3.4" do
      actor.update
    end
  end

  test "#as_json includes the expected attributes" do
    actor = Aikido::Agent::Actor.new(
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
