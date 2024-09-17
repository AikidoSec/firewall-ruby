# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::ThrottlerTest < ActiveSupport::TestCase
  setup do
    @app = Minitest::Mock.new
    @app.expect :call, [200, {}, ["OK"]], [Hash]

    @config = Aikido::Zen.config
    @settings = Aikido::Zen.runtime_settings

    @middleware = Aikido::Zen::Middleware::Throttler.new(@app)
  end

  test "allows requests when rate limiting is disabled" do
    configure "GET", "/", enabled: false

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    response = @middleware.call(env)

    assert_equal [200, {}, ["OK"]], response
    assert_mock @app
  end

  test "does not annotate the env when rate limiting is disabled for the endpoint" do
    configure "GET", "/", enabled: false

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    @middleware.call(env)

    refute env.key?("aikido.rate_limiting")
    assert_mock @app
  end

  test "allows requests when rate limiting is not configured" do
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    response = @middleware.call(env)

    assert_equal [200, {}, ["OK"]], response
    assert_mock @app
  end

  test "does not annotate the env when rate limiting is not configured" do
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    @middleware.call(env)

    refute env.key?("aikido.rate_limiting")
    assert_mock @app
  end

  test "allows requests within the configured window for a given client" do
    configure "GET", "/", max_requests: 3, period: 5

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")

    assert_equal [200, {}, ["OK"]], @middleware.call(env)

    assert_kind_of Aikido::Zen::RateLimiter::Result, env["aikido.rate_limiting"]
    assert_equal false, env["aikido.rate_limiting"].throttled?
    assert_equal "1.2.3.4", env["aikido.rate_limiting"].discriminator
    assert_equal 1, env["aikido.rate_limiting"].current_requests
    assert_equal 3, env["aikido.rate_limiting"].max_requests
    assert_equal 5, env["aikido.rate_limiting"].time_remaining

    assert_mock @app
  end

  test "blocks requests after the configured number are allowed" do
    configure "GET", "/", max_requests: 3, period: 5

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")

    # Allow 3 requests in total
    @app.expect :call, [200, {}, ["OK"]], [Hash]
    @app.expect :call, [200, {}, ["OK"]], [Hash]

    assert_equal [200, {}, ["OK"]], @middleware.call(env)
    assert_equal [200, {}, ["OK"]], @middleware.call(env)
    assert_equal [200, {}, ["OK"]], @middleware.call(env)

    assert_equal false, env["aikido.rate_limiting"].throttled?
    assert_equal "1.2.3.4", env["aikido.rate_limiting"].discriminator
    assert_equal 3, env["aikido.rate_limiting"].current_requests
    assert_equal 3, env["aikido.rate_limiting"].max_requests
    assert_equal 5, env["aikido.rate_limiting"].time_remaining

    response = @middleware.call(env)
    assert_equal [429, {"Content-Type" => "text/plain"}, ["Too many requests."]], response

    assert_equal true, env["aikido.rate_limiting"].throttled?
    assert_equal "1.2.3.4", env["aikido.rate_limiting"].discriminator
    assert_equal 3, env["aikido.rate_limiting"].current_requests
    assert_equal 3, env["aikido.rate_limiting"].max_requests
    assert_equal 5, env["aikido.rate_limiting"].time_remaining

    assert_mock @app
  end

  test "does not block requests or annotate the env for allowed IPs" do
    @settings.skip_protection_for_ips = Aikido::Zen::RuntimeSettings::IPSet.from_json(["1.2.3.4"])

    configure "GET", "/", max_requests: 3, period: 5

    # Allow 4 requests in total
    @app.expect :call, [200, {}, ["OK"]], [Hash]
    @app.expect :call, [200, {}, ["OK"]], [Hash]
    @app.expect :call, [200, {}, ["OK"]], [Hash]

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    assert_equal [200, {}, ["OK"]], @middleware.call(env)
    assert_equal [200, {}, ["OK"]], @middleware.call(env)
    assert_equal [200, {}, ["OK"]], @middleware.call(env)
    assert_equal [200, {}, ["OK"]], @middleware.call(env)

    refute env.key?("aikido.rate_limiting")
    assert_mock @app
  end

  test "the throttled response can be configured" do
    @config.rate_limited_responder = ->(request) {
      [503, {}, ["Oh no you broke the server!"]]
    }

    configure "GET", "/", max_requests: 3, period: 5

    # Allow 3 requests in total
    @app.expect :call, [200, {}, ["OK"]], [Hash]
    @app.expect :call, [200, {}, ["OK"]], [Hash]

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    assert_equal [200, {}, ["OK"]], @middleware.call(env)
    assert_equal [200, {}, ["OK"]], @middleware.call(env)
    assert_equal [200, {}, ["OK"]], @middleware.call(env)

    response = @middleware.call(env)
    assert_equal [503, {}, ["Oh no you broke the server!"]], response

    assert_mock @app
  end

  test "if current_context is already set, this reuses it" do
    configure "GET", "/", max_requests: 3, period: 5

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")

    context = Aikido::Zen::Context.from_rack_env(env)
    verifier = Minitest::Mock.new(context)
    verifier.expect :request, context.request
    Aikido::Zen.current_context = verifier

    assert_equal [200, {}, ["OK"]], @middleware.call(env)

    assert_kind_of Aikido::Zen::RateLimiter::Result, env["aikido.rate_limiting"]
    assert_equal false, env["aikido.rate_limiting"].throttled?
    assert_equal "1.2.3.4", env["aikido.rate_limiting"].discriminator
    assert_equal 1, env["aikido.rate_limiting"].current_requests
    assert_equal 3, env["aikido.rate_limiting"].max_requests
    assert_equal 5, env["aikido.rate_limiting"].time_remaining

    assert_mock @app
    assert verifier.verify
  ensure
    Aikido::Zen.current_context = nil
  end

  def configure(verb, endpoint, max_requests: 20, period: 5, enabled: true)
    route = Aikido::Zen::Route.new(verb: verb, path: endpoint)

    endpoints = @settings.endpoints.send(:to_h)
    endpoints[route] = Aikido::Zen::RuntimeSettings::ProtectionSettings.from_json(
      "forceProtectionOff" => false,
      "allowedIPAddresses" => [],
      "rateLimiting" => {
        "enabled" => enabled,
        "maxRequests" => max_requests,
        "windowSizeInMS" => period * 1000
      }
    )
  end
end
