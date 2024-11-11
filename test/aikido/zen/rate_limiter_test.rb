# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RateLimiterTest < ActiveSupport::TestCase
  include RateLimitingAssertions

  setup do
    @config = Aikido::Zen.config
    @rate_limiter = Aikido::Zen::RateLimiter.new
  end

  def assert_throttled(request, **stats)
    assert @rate_limiter.throttle?(request)

    result = request.env["aikido.rate_limiting"]
    super(result, **stats) if result
  end

  def refute_throttled(request, **stats)
    refute @rate_limiter.throttle?(request)

    result = request.env["aikido.rate_limiting"]
    super(result, **stats) if result
  end

  test "requests are allowed if rate limiting is disabled" do
    configure "GET", "/", enabled: false, max_requests: 3, period: 1

    freeze_time do
      4.times { refute_throttled build_request("GET", "/", ip: "1.2.3.4") }
    end
  end

  test "requests are throttled after the alotted number of requests" do
    configure "GET", "/", max_requests: 3, period: 1

    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 2
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3

    assert_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3
  end

  test "requests from different IPs are not throttled" do
    configure "GET", "/", max_requests: 3, period: 1

    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 2
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3

    refute_throttled build_request("GET", "/", ip: "10.0.0.1"), current: 1
    refute_throttled build_request("GET", "/", ip: "10.0.0.2"), current: 1
  end

  test "requests from different actors behind the same IP are not throttled" do
    configure "GET", "/", max_requests: 3, period: 10

    refute_throttled \
      build_request("GET", "/", ip: "1.2.3.4", user: {id: "123"}),
      current: 1, discriminator: "actor:123"
    refute_throttled \
      build_request("GET", "/", ip: "1.2.3.4", user: {id: "123"}),
      current: 2, discriminator: "actor:123"
    refute_throttled \
      build_request("GET", "/", ip: "1.2.3.4", user: {id: "123"}),
      current: 3, discriminator: "actor:123"

    refute_throttled \
      build_request("GET", "/", ip: "1.2.3.4", user: {id: "456"}),
      current: 1, discriminator: "actor:456"
    refute_throttled \
      build_request("GET", "/", ip: "1.2.3.4", user: {id: "456"}),
      current: 2, discriminator: "actor:456"
    refute_throttled \
      build_request("GET", "/", ip: "1.2.3.4", user: {id: "456"}),
      current: 3, discriminator: "actor:456"
  end

  test "requests from the same actor from different IPs are throttled" do
    configure "GET", "/", max_requests: 3, period: 10

    refute_throttled \
      build_request("GET", "/", ip: "1.2.3.4", user: {id: "123"}),
      current: 1, discriminator: "actor:123"
    refute_throttled \
      build_request("GET", "/", ip: "2.3.4.5", user: {id: "123"}),
      current: 2, discriminator: "actor:123"
    refute_throttled \
      build_request("GET", "/", ip: "3.4.5.6", user: {id: "123"}),
      current: 3, discriminator: "actor:123"

    assert_throttled \
      build_request("GET", "/", ip: "4.5.6.7", user: {id: "123"}),
      current: 3, discriminator: "actor:123"
  end

  test "requests to different endpoints are not throttled" do
    configure "GET", "/", max_requests: 3, period: 1

    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 2
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3

    refute_throttled build_request("GET", "/foo", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("GET", "/bar", ip: "1.2.3.4"), current: 1
  end

  test "requests via different HTTP methods are not throttled" do
    configure "GET", "/", max_requests: 3, period: 1

    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 2
    refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3

    refute_throttled build_request("POST", "/", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("POST", "/", ip: "1.2.3.4"), current: 2
    refute_throttled build_request("POST", "/", ip: "1.2.3.4"), current: 3
    refute_throttled build_request("POST", "/", ip: "1.2.3.4"), current: 4
  end

  test "requests to different endpoints can have different configurations" do
    configure "GET", "/foo", max_requests: 3, period: 1
    configure "GET", "/bar", max_requests: 2, period: 1

    refute_throttled build_request("GET", "/foo", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("GET", "/foo", ip: "1.2.3.4"), current: 2
    refute_throttled build_request("GET", "/foo", ip: "1.2.3.4"), current: 3
    assert_throttled build_request("GET", "/foo", ip: "1.2.3.4"), current: 3

    refute_throttled build_request("GET", "/bar", ip: "1.2.3.4"), current: 1
    refute_throttled build_request("GET", "/bar", ip: "1.2.3.4"), current: 2
    assert_throttled build_request("GET", "/bar", ip: "1.2.3.4"), current: 2
  end

  test "requests are allowed after the window slides past old requests" do
    configure "GET", "/", max_requests: 3, period: 5

    with_mocked_clock do |clock|
      clock.expect :call, 0
      refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 1, time_remaining: 5

      clock.expect :call, 1
      refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 2, time_remaining: 4

      clock.expect :call, 2
      refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3, time_remaining: 3

      clock.expect :call, 3
      assert_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3, time_remaining: 2

      # Advances 3 seconds to "free up" the request rom t=0
      clock.expect :call, 6
      refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 3, time_remaining: 0

      # Advances 2 seconds to free up 2 requests. Because this "clears" the
      # window (as the first set of requests ended at t=2), we now have 3
      # seconds remaining (the current 5 seconds window started at t=6)
      clock.expect :call, 8
      refute_throttled build_request("GET", "/", ip: "1.2.3.4"), current: 2, time_remaining: 3
    end
  end

  test "discriminator can be configured" do
    @config.rate_limiting_discriminator = ->(request) {
      request.normalized_headers["X-Client-Id"] || request.ip
    }

    configure "GET", "/", max_requests: 3, period: 5

    headers = {"HTTP_X_CLIENT_ID" => "12345"}

    refute_throttled build_request("GET", "/", headers, ip: "1.1.1.1"),
      discriminator: "12345"
    refute_throttled build_request("GET", "/", headers, ip: "2.2.2.2"),
      discriminator: "12345"
    refute_throttled build_request("GET", "/", headers, ip: "3.3.3.3"),
      discriminator: "12345"
  end

  def build_request(method, path, extra_env = {}, ip: nil, user: nil)
    env = Rack::MockRequest.env_for(path, {"REMOTE_ADDR" => ip, :method => method}.merge(extra_env))
    ctx = Aikido::Zen::Context.from_rack_env(env)
    ctx.request.actor = Aikido::Zen::Actor(user) if user
    ctx.request
  end

  def with_mocked_clock
    clock = Minitest::Mock.new
    Aikido::Zen::RateLimiter::Bucket.stub_const(:DEFAULT_CLOCK, clock) { yield clock }
    assert_mock clock
  end

  def configure(verb, endpoint, max_requests: 20, period: 5, enabled: true)
    route = Aikido::Zen::Route.new(verb: verb, path: endpoint)

    settings = Aikido::Zen::RuntimeSettings::ProtectionSettings.from_json(
      "forceProtectionOff" => false,
      "allowedIPAddresses" => [],
      "rateLimiting" => {
        "enabled" => enabled,
        "maxRequests" => max_requests,
        "windowSizeInMS" => period * 1000
      }
    )

    endpoints = Aikido::Zen.runtime_settings.endpoints.send(:to_h)
    endpoints[route] = settings
  end
end
