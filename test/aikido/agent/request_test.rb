# frozen_string_literal: true

require "test_helper"
require "aikido/agent/request/rails_request"

class Aikido::Agent::RequestTest < ActiveSupport::TestCase
  DummyRequest = Struct.new(:env)

  setup do
    @config = Aikido::Agent.config
  end

  def stub_payload(source, value, path)
    Aikido::Agent::Payload.new(value, source, path)
  end

  test "request delegates to a framework-specific object" do
    env = {}

    framework_request = DummyRequest.new(env)
    request = Aikido::Agent::Request.new(framework_request)

    assert_equal framework_request, request.__getobj__
    assert_equal env, request.env
  end

  test "the Rack::Request builder builds a Rack::Request" do
    @config.request_builder = Aikido::Agent::Request::RACK_REQUEST_BUILDER

    request = Aikido::Agent::Request.from({})
    assert_kind_of Rack::Request, request.__getobj__
  end

  test "query payloads are read from the query string" do
    env = Rack::MockRequest.env_for("/path?a=1&b=2&c=3")
    request = Aikido::Agent::Request.from(env)

    assert_includes request.payloads, stub_payload(:query, "1", "a")
  end

  test "body payloads are read from the request body" do
    env = Rack::MockRequest.env_for("/path?a=1", {
      method: "POST",
      params: {b: "2", c: "3"}
    })
    request = Aikido::Agent::Request.from(env)

    assert_includes request.payloads, stub_payload(:body, "2", "b")
  end

  test "route params are empty on the base case as they are framework dependent" do
    env = Rack::MockRequest.env_for("/some/path")
    request = Aikido::Agent::Request.from(env)

    assert_empty request.payloads.select { |payload| payload.source == :route }
  end

  test "the path for complex parameter structures is tracked correctly" do
    env = Rack::MockRequest.env_for("/path?a[n]=1&a[m]=2&b[]=3&b[]=4", {
      method: "POST",
      params: {x: ["2", "3"], y: {u: "4", v: "5", w: {i: "6", j: "7"}}}
    })
    request = Aikido::Agent::Request.from(env)

    assert_includes request.payloads, stub_payload(:query, "1", "a.n")
    assert_includes request.payloads, stub_payload(:query, "2", "a.m")
    assert_includes request.payloads, stub_payload(:query, "3", "b.0")
    assert_includes request.payloads, stub_payload(:query, "4", "b.1")

    assert_includes request.payloads, stub_payload(:body, "2", "x.0")
    assert_includes request.payloads, stub_payload(:body, "3", "x.1")

    assert_includes request.payloads, stub_payload(:body, "4", "y.u")
    assert_includes request.payloads, stub_payload(:body, "5", "y.v")
    assert_includes request.payloads, stub_payload(:body, "6", "y.w.i")
    assert_includes request.payloads, stub_payload(:body, "7", "y.w.j")
  end

  class RailsRequestTest < ActiveSupport::TestCase
    setup do
      Aikido::Agent.config.request_builder = Aikido::Agent::Request::RAILS_REQUEST_BUILDER
    end

    def stub_payload(source, value, path)
      Aikido::Agent::Payload.new(value, source, path)
    end

    test "the Rails builder builds an ActionDispatch::Request" do
      request = Aikido::Agent::Request.from({})
      assert_kind_of ActionDispatch::Request, request.__getobj__
    end

    test "query payloads are read from the query string" do
      env = Rack::MockRequest.env_for("/example/path?a=1&b=2&c=3")
      request = Aikido::Agent::Request.from(env)

      assert_includes request.payloads, stub_payload(:query, "1", "a")
    end

    test "body payloads are read from the request body" do
      env = Rack::MockRequest.env_for("/example/path?a=1", {
        method: "POST",
        params: {b: "2", c: "3"}
      })
      request = Aikido::Agent::Request.from(env)

      assert_includes request.payloads, stub_payload(:body, "2", "b")
    end

    test "route payloads are read from the data extracted by the router" do
      router = MockedRailsRouter.build do
        match "/example/:resource(/:id)(.:format)",
          via: [:get, :post],
          to: "example#test"
      end

      env = Rack::MockRequest.env_for("/example/user/23.json")
      env = router.process(env)

      request = Aikido::Agent::Request.from(env)

      assert_includes request.payloads, stub_payload(:route, "user", "resource")
      assert_includes request.payloads, stub_payload(:route, "23", "id")
      assert_includes request.payloads, stub_payload(:route, "json", "format")
      assert_includes request.payloads, stub_payload(:route, "example", "controller")
      assert_includes request.payloads, stub_payload(:route, "test", "action")
    end

    test "the path for complex parameter structures is tracked correctly" do
      env = Rack::MockRequest.env_for("/path?a[n]=1&a[m]=2&b[]=3&b[]=4", {
        method: "POST",
        params: {x: ["2", "3"], y: {u: "4", v: "5", w: {i: "6", j: "7"}}}
      })
      request = Aikido::Agent::Request.from(env)

      assert_includes request.payloads, stub_payload(:query, "1", "a.n")
      assert_includes request.payloads, stub_payload(:query, "2", "a.m")
      assert_includes request.payloads, stub_payload(:query, "3", "b.0")
      assert_includes request.payloads, stub_payload(:query, "4", "b.1")

      assert_includes request.payloads, stub_payload(:body, "2", "x.0")
      assert_includes request.payloads, stub_payload(:body, "3", "x.1")

      assert_includes request.payloads, stub_payload(:body, "4", "y.u")
      assert_includes request.payloads, stub_payload(:body, "5", "y.v")
      assert_includes request.payloads, stub_payload(:body, "6", "y.w.i")
      assert_includes request.payloads, stub_payload(:body, "7", "y.w.j")
    end
  end
end
