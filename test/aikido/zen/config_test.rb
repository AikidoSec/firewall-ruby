# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::ConfigTest < ActiveSupport::TestCase
  setup do
    @config = Aikido::Zen::Config.new
  end

  test "default values" do
    assert_equal false, @config.blocking_mode
    assert_nil @config.api_token
    assert_equal URI("https://guard.aikido.dev"), @config.api_base_url
    assert_equal URI("https://runtime.aikido.dev"), @config.runtime_api_base_url
    assert_equal 10, @config.api_timeouts[:open_timeout]
    assert_equal 10, @config.api_timeouts[:read_timeout]
    assert_equal 10, @config.api_timeouts[:write_timeout]
    assert_kind_of ::Logger, @config.logger
    assert_equal 5000, @config.max_performance_samples
    assert_equal 100, @config.max_compressed_stats
    assert_equal 200, @config.max_outbound_connections
    assert_equal 1000, @config.max_users_tracked
    assert_equal 60, @config.initial_heartbeat_delay
    assert_equal 60, @config.polling_interval
    assert_kind_of Proc, @config.blocked_ip_responder
    assert_kind_of Proc, @config.rate_limited_responder
    assert_kind_of Proc, @config.rate_limiting_discriminator
    assert_equal 3600, @config.client_rate_limit_period
    assert_equal 100, @config.client_rate_limit_max_events
    assert_equal 1800, @config.server_rate_limit_deadline
    assert_equal 20, @config.api_schema_collection_max_depth
    assert_equal 20, @config.api_schema_collection_max_properties
    assert_equal ["metadata.google.internal", "metadata.goog"], @config.imds_allowed_hosts
    assert_equal false, @config.disabled
  end

  test "can set AIKIDO_DISABLED to configure if the agent should be turned off" do
    with_env "AIKIDO_DISABLED" => "true" do
      config = Aikido::Zen::Config.new
      assert config.disabled?
    end

    with_env "AIKIDO_DISABLED" => "1" do
      config = Aikido::Zen::Config.new
      assert config.disabled?
    end

    with_env "AIKIDO_DISABLED" => "t" do
      config = Aikido::Zen::Config.new
      assert config.disabled?
    end

    with_env "AIKIDO_DISABLED" => "false" do
      config = Aikido::Zen::Config.new
      refute config.disabled?
    end

    with_env "AIKIDO_DISABLED" => "f" do
      config = Aikido::Zen::Config.new
      refute config.disabled?
    end

    with_env "AIKIDO_DISABLED" => "0" do
      config = Aikido::Zen::Config.new
      refute config.disabled?
    end

    with_env "AIKIDO_DISABLED" => "" do
      config = Aikido::Zen::Config.new
      refute config.disabled?
    end
  end

  test "can overwrite the api_base_url" do
    @config.api_base_url = "http://app.local.aikido.io"

    assert_equal URI("http://app.local.aikido.io"), @config.api_base_url
  end

  test "can overwrite the runtime_api_base_url" do
    @config.runtime_api_base_url = "http://localhost:3000"

    assert_equal URI("http://localhost:3000"), @config.runtime_api_base_url
  end

  test "can set granular timeouts" do
    @config.api_timeouts = {open_timeout: 1, read_timeout: 2, write_timeout: 3}

    assert_equal 1, @config.api_timeouts[:open_timeout]
    assert_equal 2, @config.api_timeouts[:read_timeout]
    assert_equal 3, @config.api_timeouts[:write_timeout]
  end

  test "can overwrite only some timeouts" do
    @config.api_timeouts = {open_timeout: 5}

    assert_equal 5, @config.api_timeouts[:open_timeout]
    assert_equal 10, @config.api_timeouts[:read_timeout]
    assert_equal 10, @config.api_timeouts[:write_timeout]
  end

  test "can set all timeouts to a single value" do
    @config.api_timeouts = 5

    assert_equal 5, @config.api_timeouts[:open_timeout]
    assert_equal 5, @config.api_timeouts[:read_timeout]
    assert_equal 5, @config.api_timeouts[:write_timeout]
  end

  test "can set the token" do
    @config.api_token = "S3CR3T"

    assert_equal "S3CR3T", @config.api_token
  end

  test "can overwrite blocking_mode" do
    @config.blocking_mode = true

    assert_equal true, @config.blocking_mode
  end

  test "can set the token from an ENV variable" do
    with_env "AIKIDO_TOKEN" => "S3CR3T" do
      config = Aikido::Zen::Config.new
      assert_equal "S3CR3T", config.api_token
    end
  end

  test "can override the default base URL with an ENV variable" do
    with_env "AIKIDO_BASE_URL" => "https://test.aikido.dev" do
      config = Aikido::Zen::Config.new
      assert_equal URI("https://test.aikido.dev"), config.api_base_url
    end
  end

  test "can set blocking_mode via an ENV variable" do
    with_env "AIKIDO_BLOCKING" => "1" do
      config = Aikido::Zen::Config.new
      assert_equal true, config.blocking_mode
    end
  end

  test "provides a pluggable way of parsing JSON" do
    assert_equal ["foo", "bar"], @config.json_decoder.call(%(["foo","bar"]))

    @config.json_decoder = ->(string) { string.reverse }
    assert_equal "raboof", @config.json_decoder.call("foobar")
  end

  test "provides a pluggable way of encoding JSON" do
    assert_equal %({"foo":"bar"}), @config.json_encoder.call("foo" => "bar")

    @config.json_encoder = ->(obj) { obj.class.to_s }
    assert_equal "Array", @config.json_encoder.call([1, 2])
  end

  test "the default #blocked_ip_responder returns the expected Rack response" do
    request = Minitest::Mock.new
    request.expect :ip, "1.2.3.4"

    status, headers, body = @config.blocked_ip_responder.call(request)

    assert_equal 403, status
    assert_equal({"Content-Type" => "text/plain"}, headers)
    assert_equal \
      ["Your IP address is not allowed to access this resource. (Your IP: 1.2.3.4)"],
      body

    assert_mock request
  end

  test " the default #rate_limited_responder returns the expected Rack response" do
    status, headers, body = @config.rate_limited_responder.call(Object.new)

    assert_equal 429, status
    assert_equal({"Content-Type" => "text/plain"}, headers)
    assert_equal ["Too many requests."], body
  end

  test "the default rate limiting discriminator returns the request IP" do
    request = OpenStruct.new(ip: "1.2.3.4", actor: nil)
    value = @config.rate_limiting_discriminator.call(request)

    assert_equal "1.2.3.4", value
  end

  test "the default rate limiting discriminator returns the actor id if set" do
    request = OpenStruct.new(actor: Aikido::Zen::Actor(id: 123))
    value = @config.rate_limiting_discriminator.call(request)

    assert_equal "actor:123", value
  end

  def with_env(data = {})
    env = ENV.to_h
    ENV.update(data)
    yield
  ensure
    ENV.replace(env)
  end
end
