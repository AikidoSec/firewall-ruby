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

  test ".set_tenant_id sets the tenant on the request" do
    context = Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
      Rack::MockRequest.env_for("/")
    )

    assert_nil context.request.tenant_id

    Aikido::Zen.set_tenant_id("1")

    assert_equal "1", context.request.tenant_id
  end

  test ".set_tenant_id does not fail if context is not set" do
    assert_nil Aikido::Zen.current_context

    assert_silent do
      Aikido::Zen.set_tenant_id(1)
    end
  end

  test ".idor_protect does not fail if context is not set" do
    assert_nil Aikido::Zen.current_context

    assert_silent do
      Aikido::Zen.idor_protect("SELECT 1", :common)
    end
  end

  test ".enable_idor_protection enables IDOR protection" do
    context = Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
      Rack::MockRequest.env_for("/")
    )

    assert_equal false, context.idor_protection_enabled

    Aikido::Zen.enable_idor_protection

    assert_equal true, context.idor_protection_enabled
  end

  test ".enable_idor_protection does not fail if context is not set" do
    assert_nil Aikido::Zen.current_context

    assert_silent do
      Aikido::Zen.enable_idor_protection
    end
  end

  test ".without_idor_protection executes a block with IDOR protection disabled" do
    context = Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(
      Rack::MockRequest.env_for("/")
    )

    assert_equal false, context.idor_protection_enabled

    Aikido::Zen.enable_idor_protection

    assert_equal true, context.idor_protection_enabled

    result = Aikido::Zen.without_idor_protection do
      assert_equal false, context.idor_protection_enabled
      :result
    end

    assert_equal true, context.idor_protection_enabled

    assert_equal :result, result
  end

  test ".without_idor_protection executes the block even if context is not set" do
    assert_nil Aikido::Zen.current_context

    result = Aikido::Zen.without_idor_protection do
      :result
    end

    assert_equal :result, result
  end

  test ".without_idor_protection raises ArgumentError if no block is given" do
    err = assert_raises(ArgumentError) do
      Aikido::Zen.without_idor_protection
    end

    assert_equal "block required", err.message
  end

  class TrackUserEvent < ActiveSupport::TestCase
    include StubsCurrentContext
    include WorkerHelpers

    # Override StubCurrentContext#current_context to provide a request with the
    # IP address for Aikdio::Zen::UserEvent.
    def current_context
      @current_context ||= Aikido::Zen::Context.from_rack_env({
        "REMOTE_ADDR" => "1.2.3.4"
      })
    end

    class MockAPIStream < Aikido::Zen::APIStream
      def work
        nil
      end
    end

    setup do
      Aikido::Zen.config.api_token = "TOKEN"

      # Replace the Aikido::Zen::Agent to prevent the agent from doing work.

      @worker = MockWorker.new
      @api_stream = Minitest::Mock.new(MockAPIStream.new)

      @agent = Aikido::Zen::Agent.new(
        worker: @worker,
        api_stream: @api_stream
      )

      Aikido::Zen.instance_variable_set(:@agent, @agent)
    end

    test ".track_user_event sends the named user event to the realtime API" do
      request = stub_request(:post, "https://runtime.aikido.dev/api/runtime/events")
        .with(
          body: {
            "name" => "user.login_failed",
            "userId" => "418",
            "ipAddress" => "1.2.3.4"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "TOKEN",
            "Accept" => "application/json"
          }
        )
        .to_return(status: 204, body: "")

      Aikido::Zen.set_user(
        id: "418",
        name: "I. A. Teapot"
      )

      Aikido::Zen.track_user_event("user.login_failed")

      assert_requested request
    end
  end
end
