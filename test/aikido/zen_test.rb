# frozen_string_literal: true

require "test_helper"

class Aikido::ZenTest < ActiveSupport::TestCase
  def context_for(path, env = {})
    Aikido::Zen::Context.from_rack_env(Rack::MockRequest.env_for(path, env))
  end

  test "it has a version number" do
    refute_nil ::Aikido::Zen::VERSION
  end

  test ".blocking_mode? returns the blocking mode configured at startup or set at runtime" do
    Aikido::Zen.config.blocking_mode = false

    assert_equal false, Aikido::Zen.blocking_mode?

    Aikido::Zen.runtime_settings.blocking_mode = true

    assert_equal true, Aikido::Zen.blocking_mode?
  end

  test ".request_bypassed? returns nil if there is no current context" do
    assert_nil Aikido::Zen.current_context

    assert_nil Aikido::Zen.request_bypassed?
  end

  test ".request_bypassed? returns true if the request IP is in the bypassed IP set" do
    Aikido::Zen.runtime_settings.bypassed_ips = Aikido::Zen::RuntimeSettings::IPSet.from_json(["1.2.3.4"])
    Aikido::Zen.current_context = context_for("/", "REMOTE_ADDR" => "1.2.3.4")

    assert Aikido::Zen.request_bypassed?
  end

  test ".request_bypassed? returns false if the request IP is not in the bypassed IP set" do
    Aikido::Zen.runtime_settings.bypassed_ips = Aikido::Zen::RuntimeSettings::IPSet.from_json(["1.2.3.4"])
    Aikido::Zen.current_context = context_for("/", "REMOTE_ADDR" => "5.6.7.8")

    refute Aikido::Zen.request_bypassed?
  end

  test ".request_bypassed? sticks once the request has been found bypassed, even if the settings change afterwards" do
    Aikido::Zen.runtime_settings.bypassed_ips = Aikido::Zen::RuntimeSettings::IPSet.from_json(["1.2.3.4"])
    context = Aikido::Zen.current_context = context_for("/", "REMOTE_ADDR" => "1.2.3.4")

    assert Aikido::Zen.request_bypassed?

    Aikido::Zen.runtime_settings.bypassed_ips = Aikido::Zen::RuntimeSettings::IPSet.new

    assert Aikido::Zen.request_bypassed?
    assert context.request_bypassed?
  end

  test ".request_bypassed! marks the current request as bypassed regardless of its IP" do
    Aikido::Zen.current_context = context_for("/", "REMOTE_ADDR" => "5.6.7.8")

    refute Aikido::Zen.request_bypassed?

    Aikido::Zen.request_bypassed!

    assert Aikido::Zen.request_bypassed?
  end

  test ".request_bypassed! does not fail if context is not set" do
    assert_nil Aikido::Zen.current_context

    assert_silent do
      Aikido::Zen.request_bypassed!
    end
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

  test ".calculate_rate_limits delegates to the rate limiter when there is no detached agent" do
    mock = Minitest::Mock.new
    mock.expect(:calculate_rate_limits, nil, [Object])

    Aikido::Zen.stub(:rate_limiter, mock) do
      Aikido::Zen.calculate_rate_limits(Object.new)
    end

    assert_mock mock
  end

  test ".calculate_rate_limits delegates to the detached agent when one is set" do
    mock = Minitest::Mock.new
    mock.expect(:calculate_rate_limits, nil, [Object])

    Aikido::Zen.instance_variable_set(:@worker_process_client, mock)

    Aikido::Zen.calculate_rate_limits(Object.new)

    assert_mock mock
  ensure
    Aikido::Zen.instance_variable_set(:@worker_process_client, nil)
  end

  test ".calculate_rate_limits falls back to the local rate limiter when the worker process client raises" do
    failing_client = Object.new

    def failing_client.calculate_rate_limits(request)
      raise "RPC error"
    end

    def failing_client.stop
    end

    rate_limiter_mock = Minitest::Mock.new
    rate_limiter_mock.expect(:calculate_rate_limits, :local_result, [Object])

    Aikido::Zen.instance_variable_set(:@worker_process_client, failing_client)

    result = Aikido::Zen.stub(:rate_limiter, rate_limiter_mock) do
      Aikido::Zen.calculate_rate_limits(Object.new)
    end

    assert_equal :local_result, result
    assert_mock rate_limiter_mock
  end

  test ".detect_attack_wave delegates to the local detector when there is no detached agent" do
    context = context_for("/.config", "REMOTE_ADDR" => "1.2.3.4")

    mock = Minitest::Mock.new
    mock.expect(:record, true, ["1.2.3.4", Object])

    result = Aikido::Zen.stub(:attack_wave_detector, mock) do
      Aikido::Zen.detect_attack_wave(context)
    end

    assert result
    assert_mock mock
  end

  test ".detect_attack_wave reflects record_attack_wave's outcome, even when the client is already flagged" do
    context = context_for("/.config", "REMOTE_ADDR" => "1.2.3.4")

    mock = Minitest::Mock.new
    mock.expect(:record_attack_wave, false, ["1.2.3.4", Object])

    Aikido::Zen.instance_variable_set(:@worker_process_client, mock)

    refute Aikido::Zen.detect_attack_wave(context)
    assert_mock mock
  ensure
    Aikido::Zen.instance_variable_set(:@worker_process_client, nil)
  end

  test ".detect_attack_wave never calls the detached agent when the request isn't suspicious" do
    context = context_for("/safe", "REMOTE_ADDR" => "1.2.3.4")

    mock = Minitest::Mock.new

    Aikido::Zen.instance_variable_set(:@worker_process_client, mock)

    refute Aikido::Zen.detect_attack_wave(context)
    assert_mock mock
  ensure
    Aikido::Zen.instance_variable_set(:@worker_process_client, nil)
  end

  test ".detect_attack_wave classifies locally and submits the sample when the request is suspicious" do
    context = context_for("/.config", "REMOTE_ADDR" => "1.2.3.4")

    mock = Minitest::Mock.new
    mock.expect(:record_attack_wave, true, ["1.2.3.4", Object])

    Aikido::Zen.instance_variable_set(:@worker_process_client, mock)

    assert Aikido::Zen.detect_attack_wave(context)
    assert_mock mock
  ensure
    Aikido::Zen.instance_variable_set(:@worker_process_client, nil)
  end

  test ".detect_attack_wave falls back to the local detector when the RPC call raises" do
    context = context_for("/.config", "REMOTE_ADDR" => "1.2.3.4")

    failing_client = Minitest::Mock.new
    failing_client.expect(:record_attack_wave, nil) { |*| raise "RPC error" }

    detector_mock = Minitest::Mock.new
    detector_mock.expect(:record, true, ["1.2.3.4", Object])

    Aikido::Zen.instance_variable_set(:@worker_process_client, failing_client)

    result = Aikido::Zen.stub(:attack_wave_detector, detector_mock) do
      Aikido::Zen.detect_attack_wave(context)
    end

    assert result
    assert_mock failing_client
    assert_mock detector_mock
  ensure
    Aikido::Zen.instance_variable_set(:@worker_process_client, nil)
  end

  test ".detect_attack_wave returns the samples that crossed the threshold, not just a flag" do
    context = context_for("/.config", "REMOTE_ADDR" => "1.2.3.4")
    samples = [Aikido::Zen::AttackWave::Sample.new(verb: "GET", path: "/.config")]

    mock = Minitest::Mock.new
    mock.expect(:record_attack_wave, samples, ["1.2.3.4", Object])

    Aikido::Zen.instance_variable_set(:@worker_process_client, mock)

    assert_equal samples, Aikido::Zen.detect_attack_wave(context)
    assert_mock mock
  ensure
    Aikido::Zen.instance_variable_set(:@worker_process_client, nil)
  end

  test ".detect_attack_wave returns nil when the threshold was not crossed" do
    context = context_for("/.config", "REMOTE_ADDR" => "1.2.3.4")

    mock = Minitest::Mock.new
    mock.expect(:record_attack_wave, nil, ["1.2.3.4", Object])

    Aikido::Zen.instance_variable_set(:@worker_process_client, mock)

    assert_nil Aikido::Zen.detect_attack_wave(context)
    assert_mock mock
  ensure
    Aikido::Zen.instance_variable_set(:@worker_process_client, nil)
  end
end
