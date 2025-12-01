# frozen_string_literal: true

require "test_helper"

class Aikido::ZenTest < ActiveSupport::TestCase
  test "it has a version number" do
    refute_nil ::Aikido::Zen::VERSION
  end

  test ".blocking_mode? returns the blocking mode configured at startup or set at runtime" do
    Aikido::Zen.config.blocking_mode = false

    assert_equal false, Aikido::Zen.blocking_mode?

    Aikido::Zen.runtime_settings.blocking_mode = true

    assert_equal true, Aikido::Zen.blocking_mode?
  end

  test ".track_user tracks the actor object in the collector" do
    users = Aikido::Zen.collector.users

    assert_difference -> { Aikido::Zen.collector.users.size }, +1 do
      Aikido::Zen.track_user({id: 123, name: "Alice"})
    end

    user = users.to_a.last
    assert_equal "123", user.id
    assert_equal "Alice", user.name
  end

  test ".track_user tracks the actor object in the context's request" do
    Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
      Rack::MockRequest.env_for("/")
    )

    assert_changes "Aikido::Zen.current_context.request&.actor", from: nil do
      Aikido::Zen.track_user({id: 123, name: "Alice"})
    end

    actor = Aikido::Zen.current_context.request.actor
    assert_equal "123", actor.id
    assert_equal "Alice", actor.name
  end
end
