# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::CheckAllowedAddressesTest < ActiveSupport::TestCase
  setup do
    @app = Minitest::Mock.new
    @app.expect :call, [200, {}, ["OK"]], [Hash]

    @config = Aikido::Zen.config

    @middleware = Aikido::Zen::Middleware::CheckAllowedAddresses.new(@app)
  end

  test "the request is allowed if the list of IPs is empty for this endpoint" do
    add_allowed_ips "GET", "/", ips: []

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.2.3.4")
    response = @middleware.call(env)

    assert_equal [200, {}, ["OK"]], response
    assert_mock @app
  end

  test "the request is allowed if IPs are not configured for this route" do
    add_allowed_ips "GET", "/admin", ips: ["1.2.3.4", "2.3.4.5"]

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "1.1.1.1")
    response = @middleware.call(env)

    assert_equal [200, {}, ["OK"]], response
    assert_passed_to_downstream
  end

  test "the request is allowed if the IP is explicitly set in the allow list" do
    add_allowed_ips "GET", "/admin", ips: ["1.2.3.4", "2.3.4.5"]

    env = Rack::MockRequest.env_for("/admin", "REMOTE_ADDR" => "1.2.3.4")
    response = @middleware.call(env)

    assert_equal [200, {}, ["OK"]], response
    assert_passed_to_downstream
  end

  test "the request is allowed if the IP matches a CIDR block in the allow list" do
    add_allowed_ips "GET", "/admin", ips: ["10.0.0.0/24"]

    env = Rack::MockRequest.env_for("/admin", "REMOTE_ADDR" => "10.0.0.32")
    response = @middleware.call(env)

    assert_equal [200, {}, ["OK"]], response
    assert_passed_to_downstream
  end

  test "the request is rejected if the IP is not in the allow list" do
    add_allowed_ips "GET", "/admin", ips: ["10.0.0.1", "192.168.0.0/24"]

    env = Rack::MockRequest.env_for("/admin", "REMOTE_ADDR" => "10.0.0.2")
    response = @middleware.call(env)

    assert_equal @config.blocked_ip_responder.call(Rack::Request.new(env)), response
    assert_stopped_request
  end

  test "the rejection response can be configured" do
    @config.blocked_ip_responder = ->(req) {
      [403, {"Content-Type" => "application/json"}, [%({"error":"ip_rejected","ip":"#{req.ip}"})]]
    }

    add_allowed_ips "GET", "/admin", ips: ["10.0.0.0/24"]

    env = Rack::MockRequest.env_for("/admin", "REMOTE_ADDR" => "1.2.3.4")
    status, headers, body = @middleware.call(env)

    assert_equal 403, status
    assert_equal({"Content-Type" => "application/json"}, headers)
    assert_equal [%({"error":"ip_rejected","ip":"1.2.3.4"})], body
  end

  test "if current_context is already set, this reuses it" do
    add_allowed_ips "GET", "/admin", ips: ["10.0.0.0/24"]

    env = Rack::MockRequest.env_for("/admin", "REMOTE_ADDR" => "10.0.0.1")

    context = Aikido::Zen::Context.from_rack_env(env)
    verifier = Minitest::Mock.new(context)
    verifier.expect :request, context.request
    Aikido::Zen.current_context = verifier

    response = @middleware.call(env)

    assert_equal [200, {}, ["OK"]], response
    assert_mock @app
    assert verifier.verify
  ensure
    Aikido::Zen.current_context = nil
  end

  def assert_passed_to_downstream
    assert_mock @app
  end

  def assert_stopped_request
    assert_raises { @app.verify }
  end

  def add_allowed_ips(verb, path, ips:)
    definition = build_endpoint_response({
      "method" => verb,
      "route" => path,
      "allowedIPAddresses" => ips
    })

    settings = Aikido::Zen.runtime_settings
    endpoints = settings.endpoints.send(:to_h).map { |route, settings|
      build_endpoint_response({
        "method" => route.verb,
        "route" => route.path,
        "allowedIPAddresses" => settings.allowed_ips
      })
    }

    settings.endpoints = Aikido::Zen::RuntimeSettings::Endpoints.from_json(
      endpoints << definition
    )
  end

  def build_route(verb: "GET", path: "/")
    Aikido::Zen::Route.new(verb: verb, path: path)
  end

  def build_endpoint_response(overrides = {})
    {
      "forceProtectionOff" => false,
      "allowedIPAddresses" => [],
      "rateLimiting" => {
        "enabled" => false, "maxRequests" => 1000, "windowSizeInMS" => 300000
      }
    }.merge(overrides)
  end
end
