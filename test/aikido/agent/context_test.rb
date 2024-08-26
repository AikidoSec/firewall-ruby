# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::ContextTest < ActiveSupport::TestCase
  DummyRequest = Struct.new(:env)

  setup do
    @config = Aikido::Agent.config
  end

  def stub_payload(source, value, path)
    Aikido::Agent::Payload.new(value, source, path)
  end

  test "context links to a framework-specific request object" do
    env = {}

    framework_request = DummyRequest.new(env)
    context = Aikido::Agent::Context.new(framework_request)

    assert_equal framework_request, context.request
  end

  test "the Rack::Request builder wraps a Rack::Request-based Context" do
    @config.request_builder = Aikido::Agent::Context::RACK_REQUEST_BUILDER

    context = Aikido::Agent::Context.from_rack_env({})
    assert_kind_of Aikido::Agent::Request, context.request
    assert_kind_of Rack::Request, context.request.__getobj__
  end

  test "query payloads are read from the query string" do
    env = Rack::MockRequest.env_for("/path?a=1&b=2&c=3")
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_includes context.payloads, stub_payload(:query, "1", "a")
  end

  test "body payloads are read from the request body" do
    env = Rack::MockRequest.env_for("/path?a=1", {
      method: "POST",
      params: {b: "2", c: "3"}
    })
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_includes context.payloads, stub_payload(:body, "2", "b")
  end

  test "JSON bodies are not parsed by the Rack implementation" do
    env = Rack::MockRequest.env_for("/path?a=1", {
      :method => "POST",
      :input => %({"test":"value","nested":{"hash":"data"},"array":[1, 2, 3]}),
      "CONTENT_TYPE" => "application/json"
    })
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_empty context.payloads.select { |payload| payload.source == :body }
  end

  test "route params are empty on the base case as they are framework dependent" do
    env = Rack::MockRequest.env_for("/some/path")
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_empty context.payloads.select { |payload| payload.source == :route }
  end

  test "header params are sourced from the normalized headers" do
    env = Rack::MockRequest.env_for("/path", {
      "HTTP_ACCEPT" => "application/json",
      "HTTP_USER_AGENT" => "Test/UA",
      "HTTP_AUTHORIZATION" => "Token S3CR37"
    })
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_includes context.payloads, stub_payload(:header, "application/json", "Accept")
    assert_includes context.payloads, stub_payload(:header, "Test/UA", "User-Agent")
    assert_includes context.payloads, stub_payload(:header, "Token S3CR37", "Authorization")
  end

  test "cookie params are sourced from the Cookie header" do
    env = Rack::MockRequest.env_for("/path", {
      "HTTP_COOKIE" => "c1=foo; c2=bar; c3=baz"
    })
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_includes context.payloads, stub_payload(:cookie, "foo", "c1")
    assert_includes context.payloads, stub_payload(:cookie, "bar", "c2")
    assert_includes context.payloads, stub_payload(:cookie, "baz", "c3")
  end

  test "subdomain params are empty for the base case as Rack doesn't provide tooling for this" do
    env = Rack::MockRequest.env_for("https://test.example.com/path")
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_empty context.payloads.select { |payload| payload.source == :subdomain }
  end

  test "the path for complex parameter structures is tracked correctly" do
    env = Rack::MockRequest.env_for("/path?a[n]=1&a[m]=2&b[]=3&b[]=4", {
      method: "POST",
      params: {x: ["2", "3"], y: {u: "4", v: "5", w: {i: "6", j: "7"}}}
    })
    context = Aikido::Agent::Context.from_rack_env(env)

    assert_includes context.payloads, stub_payload(:query, "1", "a.n")
    assert_includes context.payloads, stub_payload(:query, "2", "a.m")
    assert_includes context.payloads, stub_payload(:query, "3", "b.0")
    assert_includes context.payloads, stub_payload(:query, "4", "b.1")

    assert_includes context.payloads, stub_payload(:body, "2", "x.0")
    assert_includes context.payloads, stub_payload(:body, "3", "x.1")

    assert_includes context.payloads, stub_payload(:body, "4", "y.u")
    assert_includes context.payloads, stub_payload(:body, "5", "y.v")
    assert_includes context.payloads, stub_payload(:body, "6", "y.w.i")
    assert_includes context.payloads, stub_payload(:body, "7", "y.w.j")
  end

  class RailsRequestTest < ActiveSupport::TestCase
    setup do
      Aikido::Agent.config.request_builder = Aikido::Agent::Context::RAILS_REQUEST_BUILDER
    end

    def env_for(path, env = {})
      env.reverse_merge!(Rails.application.env_config)
      Rack::MockRequest.env_for(path, env)
    end

    def build_cookie_header(&block)
      req = ActionDispatch::Request.new(env_for("/", {}))
      block.call(req.cookie_jar)
      req.cookie_jar.to_header
    end

    def stub_payload(source, value, path)
      Aikido::Agent::Payload.new(value, source, path)
    end

    test "the Rails builder wraps a ActionDispatch::Request" do
      context = Aikido::Agent::Context.from_rack_env({})
      assert_kind_of Aikido::Agent::Request, context.request
      assert_kind_of ActionDispatch::Request, context.request.__getobj__
    end

    test "query payloads are read from the query string" do
      env = env_for("/example/path?a=1&b=2&c=3")
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:query, "1", "a")
    end

    test "body payloads are read from the request body" do
      env = env_for("/example/path?a=1", {
        method: "POST",
        params: {b: "2", c: "3"}
      })
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:body, "2", "b")
    end

    test "body payloads are read from JSON-encoded bodies" do
      env = env_for("/example", {
        :method => "POST",
        :input => %({"test":"value","nested":{"hash":"data"},"array":[1, 2, 3]}),
        "CONTENT_TYPE" => "application/json"
      })
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:body, "value", "test")
      assert_includes context.payloads, stub_payload(:body, "data", "nested.hash")
      assert_includes context.payloads, stub_payload(:body, 1, "array.0")
      assert_includes context.payloads, stub_payload(:body, 2, "array.1")
      assert_includes context.payloads, stub_payload(:body, 3, "array.2")
    end

    test "route payloads are read from the data extracted by the router" do
      router = MockedRailsRouter.build do
        match "/example/:resource(/:id)(.:format)",
          via: [:get, :post],
          to: "example#test"
      end

      env = env_for("/example/user/23.json")
      env = router.process(env)

      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:route, "user", "resource")
      assert_includes context.payloads, stub_payload(:route, "23", "id")
      assert_includes context.payloads, stub_payload(:route, "json", "format")
      assert_includes context.payloads, stub_payload(:route, "example", "controller")
      assert_includes context.payloads, stub_payload(:route, "test", "action")
    end

    test "header params are sourced from the normalized headers" do
      env = env_for("/path", {
        "HTTP_ACCEPT" => "application/json",
        "HTTP_USER_AGENT" => "Test/UA",
        "HTTP_AUTHORIZATION" => "Token S3CR37"
      })
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:header, "application/json", "Accept")
      assert_includes context.payloads, stub_payload(:header, "Test/UA", "User-Agent")
      assert_includes context.payloads, stub_payload(:header, "Token S3CR37", "Authorization")
    end

    test "cookie params are sourced from the Cookie header" do
      env = env_for("/path", {
        "HTTP_COOKIE" => build_cookie_header { |cookies|
          cookies["c1"] = {value: "foo", expires: Date.tomorrow}
          cookies["c2"] = "bar"
          cookies["c3"] = "baz"
        }
      })
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:cookie, "foo", "c1")
      assert_includes context.payloads, stub_payload(:cookie, "bar", "c2")
      assert_includes context.payloads, stub_payload(:cookie, "baz", "c3")
    end

    test "cookie params includes the plain-text values of encrypted cookies" do
      env = env_for("/path", {
        "HTTP_COOKIE" => build_cookie_header { |cookies|
          cookies["c1"] = {value: "foo", expires: Date.tomorrow}
          cookies.encrypted["c2"] = "encrypted_value"
          cookies["c3"] = "baz"
        }
      })
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:cookie, "foo", "c1")
      assert_includes context.payloads, stub_payload(:cookie, "encrypted_value", "c2")
      assert_includes context.payloads, stub_payload(:cookie, "baz", "c3")
    end

    test "cookie params includes the plain-text values of signed cookies" do
      env = env_for("/path", {
        "HTTP_COOKIE" => build_cookie_header { |cookies|
          cookies["c1"] = {value: "foo", expires: Date.tomorrow}
          cookies.signed["c2"] = "signed_value"
          cookies["c3"] = "baz"
        }
      })
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:cookie, "foo", "c1")
      assert_includes context.payloads, stub_payload(:cookie, "signed_value", "c2")
      assert_includes context.payloads, stub_payload(:cookie, "baz", "c3")
    end

    test "subdomain params are sourced from the request URL, based on the configured TLD length" do
      with_tld_length 1 do
        env = env_for("https://test.domain.example.com/path")
        context = Aikido::Agent::Context.from_rack_env(env)

        assert_includes context.payloads, stub_payload(:subdomain, "test", "0")
        assert_includes context.payloads, stub_payload(:subdomain, "domain", "1")
      end

      with_tld_length 2 do
        env = env_for("https://test.domain.example.com/path")
        context = Aikido::Agent::Context.from_rack_env(env)

        assert_includes context.payloads, stub_payload(:subdomain, "test", "0")
        refute_includes context.payloads, stub_payload(:subdomain, "domain", "1")
      end

      with_tld_length 3 do
        env = env_for("https://test.domain.example.com/path")
        context = Aikido::Agent::Context.from_rack_env(env)

        assert_empty context.payloads.select { |payload| payload.source == :subdomain }
      end
    end

    test "the path for complex parameter structures is tracked correctly" do
      env = env_for("/path?a[n]=1&a[m]=2&b[]=3&b[]=4", {
        method: "POST",
        params: {x: ["2", "3"], y: {u: "4", v: "5", w: {i: "6", j: "7"}}}
      })
      context = Aikido::Agent::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:query, "1", "a.n")
      assert_includes context.payloads, stub_payload(:query, "2", "a.m")
      assert_includes context.payloads, stub_payload(:query, "3", "b.0")
      assert_includes context.payloads, stub_payload(:query, "4", "b.1")

      assert_includes context.payloads, stub_payload(:body, "2", "x.0")
      assert_includes context.payloads, stub_payload(:body, "3", "x.1")

      assert_includes context.payloads, stub_payload(:body, "4", "y.u")
      assert_includes context.payloads, stub_payload(:body, "5", "y.v")
      assert_includes context.payloads, stub_payload(:body, "6", "y.w.i")
      assert_includes context.payloads, stub_payload(:body, "7", "y.w.j")
    end

    # Set the TLD length when parsing hostnames in order to determine subdomains
    # for the duration of the passed block.
    def with_tld_length(value)
      original_tld_length = ActionDispatch::Http::URL.tld_length
      ActionDispatch::Http::URL.tld_length = value
      yield
    ensure
      ActionDispatch::Http::URL.tld_length = original_tld_length
    end
  end
end
