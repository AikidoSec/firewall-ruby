# frozen_string_literal: true

require "test_helper"
require "aikido/zen/sinks/action_controller"

class Aikido::Zen::Sinks::ActionControllerTest < ActiveSupport::TestCase
  # Controller-like object that implements the before/after/around_action
  # interface.
  class AbstractFakeController
    include ActiveSupport::Callbacks
    prepend Aikido::Zen::Sinks::ActionController::Extensions

    define_callbacks :process_action,
      terminator: ->(target, prev_callback) {
        prev_callback.call
        !target.response.nil?
      }

    %i[before after around].each do |hook|
      define_singleton_method :"#{hook}_action" do |&block|
        set_callback(:process_action, hook, &block)
      end
    end

    attr_reader :sequence, :headers
    attr_accessor :request, :response

    def initialize
      @sequence = []
      @headers = {}
    end

    def process_action(env)
      env = Rails.application.env_config.merge(env)
      self.request = ActionDispatch::Request.new(env)

      run_callbacks(:process_action) do
        action = ROUTER.fetch([request.method, request.path], :not_found)
        send(action)
      end
    end

    ROUTER = {
      ["GET", "/"] => :get_root,
      ["GET", "/another"] => :get_another
    }

    def render(**response)
      self.response = response
    end
  end

  class FakeController < AbstractFakeController
    before_action do |controller|
      controller.sequence << :before
    end

    before_action do |controller|
      controller.sequence << :auth_check

      if controller.request.env["user_data"]
        Aikido::Zen.track_user(controller.request.env["user_data"])
      elsif controller.only_allow_authenticated?
        controller.render(status: 401)
      end
    end

    after_action do |controller|
      controller.sequence << :after
    end

    around_action do |controller, block|
      controller.sequence << :before_around
      block.call
      controller.sequence << :after_around
    end

    def initialize(only_allow_authenticated: false)
      super()
      @only_allow_authenticated = only_allow_authenticated
    end

    def only_allow_authenticated?
      @only_allow_authenticated
    end

    def get_root
      sequence << :get_root
      render plain: "success", status: 200
    end

    def get_another
      sequence << :get_another
      render plain: "success", status: 200
    end

    def not_found
      sequence << :not_found
      render plain: "not found", status: 404
    end
  end

  def assert_throttled(controller)
    assert_equal({status: 429, plain: "Too many requests."}, controller.response)
    assert_hash_subset_of controller.headers, {"Content-Type" => "text/plain"}
  end

  def refute_throttled(controller)
    refute_equal({status: 429, plain: "Too many requests."}, controller.response)
  end

  test "controller executes normally when no rate limiting is configured" do
    request = build_request("GET", "/", ip: "1.2.3.4", user: {id: 1234})
    controller = make_request(request)

    refute_throttled(controller)
    assert_equal \
      [:before, :auth_check, :before_around, :get_root, :after_around, :after],
      controller.sequence
  end

  test "controller executes normally when a callback halts early" do
    request = build_request("GET", "/", ip: "1.2.3.4")
    controller = make_request(request, only_allow_authenticated: true)

    refute_throttled(controller)
    assert_equal [:before, :auth_check, :after], controller.sequence
  end

  test "controller rate limits requests when configured" do
    configure "GET", "/", max_requests: 3, period: 10

    request = build_request("GET", "/", ip: "1.2.3.4")

    refute_throttled make_request(request)
    refute_throttled make_request(request)
    refute_throttled make_request(request)

    assert_throttled make_request(request)
  end

  test "controller does not rate limit reuests from different IPs" do
    configure "GET", "/", max_requests: 3, period: 10

    from_first_ip = build_request("GET", "/", ip: "1.2.3.4")
    from_second_ip = build_request("GET", "/", ip: "4.3.2.1")

    refute_throttled make_request(from_first_ip)
    refute_throttled make_request(from_first_ip)
    refute_throttled make_request(from_first_ip)

    refute_throttled make_request(from_second_ip)
  end

  test "controller does not rate limit requests to endpoints that aren't configured" do
    configure "GET", "/", max_requests: 3, period: 10

    unconfigured_endpoint = build_request("GET", "/another", ip: "1.2.3.4")

    refute_throttled make_request(unconfigured_endpoint)
    refute_throttled make_request(unconfigured_endpoint)
    refute_throttled make_request(unconfigured_endpoint)
    refute_throttled make_request(unconfigured_endpoint)
  end

  test "controller does not rate limit requests with different HTTP methods" do
    configure "GET", "/", max_requests: 3, period: 10

    post_request = build_request("POST", "/", ip: "1.2.3.4")

    refute_throttled make_request(post_request)
    refute_throttled make_request(post_request)
    refute_throttled make_request(post_request)
    refute_throttled make_request(post_request)
  end

  test "authenticated requests are throttled by User ID, not IP" do
    configure "GET", "/", max_requests: 3, period: 10

    from_user_1 = build_request("GET", "/", ip: "1.2.3.4", user: {id: 123})
    from_user_2 = build_request("GET", "/", ip: "1.2.3.4", user: {id: 456})

    refute_throttled make_request(from_user_1)
    refute_throttled make_request(from_user_1)
    refute_throttled make_request(from_user_1)

    refute_throttled make_request(from_user_2)
    refute_throttled make_request(from_user_2)
    refute_throttled make_request(from_user_2)

    assert_throttled make_request(from_user_1)
    assert_throttled make_request(from_user_2)
  end

  test "requests to different endpoints can have different configurations" do
    configure "GET", "/", max_requests: 3, period: 1
    configure "GET", "/another", max_requests: 2, period: 1

    root = build_request("GET", "/", ip: "1.2.3.4")
    other = build_request("GET", "/another", ip: "1.2.3.4")

    refute_throttled make_request(root)
    refute_throttled make_request(root)
    refute_throttled make_request(root)

    refute_throttled make_request(other)
    refute_throttled make_request(other)

    assert_throttled make_request(root)
    assert_throttled make_request(other)
  end

  test "requests are allowed after the window slides past old requests" do
    configure "GET", "/", max_requests: 3, period: 5

    request = build_request("GET", "/", ip: "1.2.3.4")

    with_mocked_clock do |clock|
      clock.expect :call, 0
      refute_throttled make_request(request)

      clock.expect :call, 1
      refute_throttled make_request(request)

      clock.expect :call, 2
      refute_throttled make_request(request)

      clock.expect :call, 3
      assert_throttled make_request(request)

      # Advances 3 seconds to "free up" the request rom t=0
      clock.expect :call, 6
      refute_throttled make_request(request)

      # Advances 2 seconds to free up 2 requests. Because this "clears" the
      # window (as the first set of requests ended at t=2), we now have 3
      # seconds remaining (the current 5 seconds window started at t=6)
      clock.expect :call, 8
      refute_throttled make_request(request)
    end
  end

  def build_request(method, path, extra_env = {}, ip: nil, user: nil)
    env = Rack::MockRequest.env_for(path, {"REMOTE_ADDR" => ip, :method => method}.merge(extra_env))
    env["user_data"] = user if user
    ctx = env[Aikido::Zen::ENV_KEY] = Aikido::Zen::Context.from_rack_env(env)
    Aikido::Zen.current_context = ctx
    ctx.request
  end

  def make_request(request, only_allow_authenticated: false)
    controller = FakeController.new(only_allow_authenticated: only_allow_authenticated)
    controller.process_action(request.env)
    controller
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

  def with_mocked_clock
    clock = Minitest::Mock.new
    Aikido::Zen::RateLimiter::Bucket.stub_const(:DEFAULT_CLOCK, clock) { yield clock }
    assert_mock clock
  end
end
