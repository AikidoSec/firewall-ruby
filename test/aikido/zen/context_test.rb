# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::ContextTest < ActiveSupport::TestCase
  include JWTHelpers

  DummyRequest = Struct.new(:env)

  # Rack 3 does not require rack.input to respond to #rewind.
  class NonRewindableInput
    def initialize(string)
      @io = StringIO.new(string)
    end

    def set_encoding(*args)
      @io.set_encoding(*args)
    end

    def read(*args)
      @io.read(*args)
    end

    def gets(*args)
      @io.gets(*args)
    end

    def each(&block)
      @io.each(&block)
    end

    def close
      @io.close
    end
  end

  def jwt_payloads(value, source: :body)
    request = DummyRequest.new({})
    Aikido::Zen::Context.new(request) { {source => {"token" => value}} }.payloads
  end

  test "context links to a framework-specific request object" do
    env = {}

    framework_request = DummyRequest.new(env)
    context = Aikido::Zen::Context.new(framework_request)

    assert_equal framework_request, context.request
  end

  test "payload extraction does not recurse past the configured maximum depth" do
    Aikido::Zen.config.extract_payloads_max_depth = 2

    request = DummyRequest.new({})
    data = {"a" => {"b" => "kept at the depth limit", "c" => {"d" => "dropped past the depth limit"}}}
    context = Aikido::Zen::Context.new(request) { {body: data} }

    assert_includes context.payloads, Aikido::Zen::Payload.new("kept at the depth limit", :body, "a.b")
    refute_includes context.payloads, Aikido::Zen::Payload.new("dropped past the depth limit", :body, "a.c.d")
  end

  test "payload extraction does not URL-decode past the configured maximum" do
    Aikido::Zen.config.extract_payloads_max_url_decoded_variants = 1

    request = DummyRequest.new({})
    context = Aikido::Zen::Context.new(request) { {body: {"a" => "x%252520y"}} }

    assert_includes context.payloads, Aikido::Zen::Payload.new("x%2520y", :body, "a")
    refute_includes context.payloads, Aikido::Zen::Payload.new("x%20y", :body, "a")
  end

  test "payload extraction caps recursion depth to prevent a stack overflow" do
    data = "leaf"
    10_000.times { data = {"k" => data} }

    request = DummyRequest.new({})
    context = Aikido::Zen::Context.new(request) { {body: data} }

    assert_nothing_raised { context.payloads }
  end

  test "the File.join special case for arrays does not stack overflow on deeply nested arrays" do
    Aikido::Zen.config.harden = false

    data = "leaf"
    200_000.times { data = [data] }

    request = DummyRequest.new({})
    context = Aikido::Zen::Context.new(request) { {query: data} }

    assert_nothing_raised { context.payloads }
  end

  test "payload extraction adds the JWT payload keys and values under the <jwt> path" do
    jwt = encode_jwt({"sub" => "../../etc/passwd", "nested" => {"role" => "admin"}, "list" => ["a", "b"]})

    payloads = jwt_payloads(jwt)

    assert_includes payloads, Aikido::Zen::Payload.new(jwt, :body, "token")
    assert_includes payloads, Aikido::Zen::Payload.new("sub", :body, "token<jwt>.sub")
    assert_includes payloads, Aikido::Zen::Payload.new("../../etc/passwd", :body, "token<jwt>.sub")
    assert_includes payloads, Aikido::Zen::Payload.new("admin", :body, "token<jwt>.nested.role")
    assert_includes payloads, Aikido::Zen::Payload.new("a", :body, "token<jwt>.list.0")
    assert_includes payloads, Aikido::Zen::Payload.new("b", :body, "token<jwt>.list.1")
  end

  test "payload extraction places JWT claims under the path of the string that holds the JWT" do
    jwt = encode_jwt({"sub" => "top"})

    request = DummyRequest.new({})
    context = Aikido::Zen::Context.new(request) { {body: {"user" => {"session" => jwt}}} }

    assert_includes context.payloads, Aikido::Zen::Payload.new("top", :body, "user.session<jwt>.sub")
  end

  test "payload extraction extracts JWT claims when only a URL-decoded variant is a JWT" do
    jwt = encode_jwt({"user" => "' OR 1=1--"})

    [jwt.gsub(".", "%2E"), jwt.gsub(".", "%252E")].each do |encoded|
      assert_includes jwt_payloads(encoded),
        Aikido::Zen::Payload.new("' OR 1=1--", :body, "token<jwt>.user"),
        "expected the claim from #{encoded.inspect}"
    end
  end

  test "payload extraction extracts JWT claims once when the token and all its variants are JWTs" do
    # The five variants change only the header so the payload part is the same.
    jwt = ["%252525252541", encode_jwt_part({"user" => "' OR 1=1--"}), "signature"].join(".")

    assert_equal 1, jwt_payloads(jwt).count { |payload| payload.value == "' OR 1=1--" }
  end

  test "payload extraction extracts JWT claims when a deeper variant is no longer a JWT" do
    # The 2nd variant adds a dot to the header so it is no longer a JWT.
    jwt = ["a%252Eb", encode_jwt_part({"user" => "' OR 1=1--"}), "signature"].join(".")

    assert_includes jwt_payloads(jwt), Aikido::Zen::Payload.new("' OR 1=1--", :body, "token<jwt>.user")
  end

  test "payload extraction still adds the URL-decoded variants of a string that holds a JWT" do
    # The two variants change only the header so the payload part is the same.
    jwt = ["%2541", encode_jwt_part({"user" => "x"}), "signature"].join(".")

    assert_includes jwt_payloads(jwt), Aikido::Zen::Payload.new("A.eyJ1c2VyIjoieCJ9.signature", :body, "token")
  end

  test "payload extraction does not extract JWT claims past the configured maximum depth" do
    Aikido::Zen.config.extract_payloads_max_depth = 2

    jwt = encode_jwt({"sub" => "too deep"})

    refute_includes jwt_payloads(jwt).map(&:value), "too deep"
  end

  test "payload extraction treats a dotted string that is not a JWT as a plain string" do
    payloads = jwt_payloads("a.b.c")

    assert_equal [
      Aikido::Zen::Payload.new("token", :body, "token"),
      Aikido::Zen::Payload.new("a.b.c", :body, "token")
    ], payloads
  end

  module GenericTests
    extend ActiveSupport::Testing::Declarative

    def multipart_env(fields)
      boundary = "AaB03x"
      parts = fields.flat_map do |name, value|
        ["--#{boundary}", %(Content-Disposition: form-data; name="#{name}"), "", value]
      end

      {
        :method => "POST",
        :input => [*parts, "--#{boundary}--", ""].join("\r\n"),
        "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}"
      }
    end

    test "query payloads are read from the query string" do
      context = build_context_for("/path?a=1&b=2&c=3")

      assert_includes context.payloads, stub_payload(:query, "1", "a")
      assert_includes context.payloads, stub_payload(:query, "2", "b")
      assert_includes context.payloads, stub_payload(:query, "3", "c")
    end

    test "body payloads are read from the request body" do
      context = build_context_for("/example/path?a=1", {
        method: "POST",
        params: {b: "2", c: "3"}
      })

      assert_includes context.payloads, stub_payload(:body, "2", "b")
      assert_includes context.payloads, stub_payload(:body, "3", "c")
    end

    test "form bodies are extracted without consuming the request body" do
      input = StringIO.new("username=mallory&role=admin")
      context = build_context_for("/example/path", {
        :method => "POST",
        :input => input,
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })

      assert_includes context.payloads, stub_payload(:body, "admin", "role")
      assert_equal "username=mallory&role=admin", input.read
    end

    test "form bodies are extracted without consuming a request body that cannot be rewound" do
      env = env_for("/example/path", {
        :method => "POST",
        :input => NonRewindableInput.new("username=mallory&role=admin"),
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })
      context = Aikido::Zen::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:body, "admin", "role")
      assert_equal "username=mallory&role=admin", env["rack.input"].read
    end

    test "form bodies are extracted without consuming a replacement request body that cannot be rewound" do
      env = env_for("/example/path", {
        :method => "POST",
        :input => "username=mallory",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })
      context = Aikido::Zen::Context.from_rack_env(env)
      env["rack.input"] = NonRewindableInput.new("username=mallory&role=admin")

      assert_includes context.payloads, stub_payload(:body, "admin", "role")
      assert_equal "username=mallory&role=admin", env["rack.input"].read
    end

    test "form bodies are extracted without caching the parsed form on the request env" do
      env = env_for("/example/path", {
        :method => "POST",
        :input => "username=mallory&role=admin",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })
      context = Aikido::Zen::Context.from_rack_env(env)
      context.payloads

      assert_nil context.request.env["rack.request.form_hash"]
      assert_nil context.request.env["rack.request.form_pairs"]
    end

    test "body payloads are read from multipart-encoded bodies" do
      context = build_context_for("/example/path", multipart_env("username" => "mallory", "role" => "admin"))

      assert_includes context.payloads, stub_payload(:body, "mallory", "username")
      assert_includes context.payloads, stub_payload(:body, "admin", "role")
    end

    test "header params are sourced from the normalized headers" do
      context = build_context_for("/path", {
        "HTTP_ACCEPT" => "application/json",
        "HTTP_USER_AGENT" => "Test/UA",
        "HTTP_AUTHORIZATION" => "Token S3CR37"
      })

      assert_includes context.payloads, stub_payload(:header, "application/json", "Accept")
      assert_includes context.payloads, stub_payload(:header, "Test/UA", "User-Agent")
      assert_includes context.payloads, stub_payload(:header, "Token S3CR37", "Authorization")
    end

    test "cookie params are sourced from the Cookie header" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => "c1=foo; c2=bar; c3=baz"
      })

      assert_includes context.payloads, stub_payload(:cookie, "foo", "c1")
      assert_includes context.payloads, stub_payload(:cookie, "bar", "c2")
      assert_includes context.payloads, stub_payload(:cookie, "baz", "c3")
    end

    test "URL-decoded variants of double-encoded query values are extracted" do
      context = build_context_for("/path?q=%2527+OR+1")

      assert_includes context.payloads, stub_payload(:query, "%27 OR 1", "q")
      assert_includes context.payloads, stub_payload(:query, "' OR 1", "q")
    end

    test "URL-decoded variants of header values are extracted" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "%27+OR+1"})

      assert_includes context.payloads, stub_payload(:header, "%27+OR+1", "X-Test")
      assert_includes context.payloads, stub_payload(:header, "'+OR+1", "X-Test")
    end

    test "undecoded values are extracted alongside their URL-decoded variants" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%2520b"})

      assert_includes context.payloads, stub_payload(:header, "a%2520b", "X-Test")
      assert_includes context.payloads, stub_payload(:header, "a%20b", "X-Test")
      assert_includes context.payloads, stub_payload(:header, "a b", "X-Test")
    end

    test "strings without percent-encoding are extracted once" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "plain"})

      assert_equal 1, context.payloads.count { |payload| payload.source == :header && payload.value == "plain" }
    end

    test "values are URL-decoded repeatedly" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%252520b"})

      assert_includes context.payloads, stub_payload(:header, "a%2520b", "X-Test")
      assert_includes context.payloads, stub_payload(:header, "a%20b", "X-Test")
      assert_includes context.payloads, stub_payload(:header, "a b", "X-Test")
    end

    test "values are URL-decoded at most five times" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%252525252520b"})

      assert_includes context.payloads, stub_payload(:header, "a%20b", "X-Test")
      refute_includes context.payloads, stub_payload(:header, "a b", "X-Test")
    end

    test "URL-decoding does not turn plus signs into spaces" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a+b%20c"})

      assert_includes context.payloads, stub_payload(:header, "a+b c", "X-Test")
      refute_includes context.payloads, stub_payload(:header, "a b c", "X-Test")
    end

    test "invalid percent-encoded sequences are left as they are" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "%27%zz%2"})

      assert_includes context.payloads, stub_payload(:header, "%27%zz%2", "X-Test")
      assert_includes context.payloads, stub_payload(:header, "'%zz%2", "X-Test")
    end

    test "URL-decoded variants that are not valid UTF-8 are extracted as they are" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%ffb"})

      assert_includes context.payloads, stub_payload(:header, "a%ffb", "X-Test")
      assert_includes context.payloads, stub_payload(:header, "a\xFFb", "X-Test")
    end

    test "keys are not URL-decoded" do
      context = build_context_for("/path", {"HTTP_COOKIE" => "a%2520b=1"})

      refute context.payloads.any? { |payload| payload.source == :cookie && payload.value == "a b" }
    end

    test "the path for complex parameter structures is tracked correctly" do
      context = build_context_for("/path?a[n]=1&a[m]=2&b[]=3&b[]=4", {
        method: "POST",
        params: {x: ["2", "3"], y: {u: "4", v: "5", w: {i: "6", j: "7"}}}
      })

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

    test "relative path arrays in complex parameter structures are joined for File.join" do
      context = build_context_for("/path?path1[]=..&path1[]=..&path1[]=..&path1[]=etc&path1[]=passwd", {
        method: "POST",
        params: {path2: ["..", "..", "..", "etc", "passwd"]}
      })

      assert_includes context.payloads, stub_payload(:query, "../../../etc/passwd", "path1<File.join>")

      assert_includes context.payloads, stub_payload(:body, "../../../etc/passwd", "path2<File.join>")
    end

    test "absolute path arrays in complex parameter structures are joined for File.join" do
      context = build_context_for("/path?path1[]=&path1[]=etc&path1[]=passwd&path2[]=/&path2[]=etc&path2[]=passwd&&path3[]=/etc&path3[]=passwd", {
        method: "POST",
        params: {path4: ["/", "etc", "passwd"], path5: ["", "etc", "passwd"], path6: ["/etc", "passwd"]}
      })

      assert_includes context.payloads, stub_payload(:query, "/etc/passwd", "path1<File.join>")
      assert_includes context.payloads, stub_payload(:query, "/etc/passwd", "path2<File.join>")
      assert_includes context.payloads, stub_payload(:query, "/etc/passwd", "path3<File.join>")

      assert_includes context.payloads, stub_payload(:body, "/etc/passwd", "path4<File.join>")
      assert_includes context.payloads, stub_payload(:body, "/etc/passwd", "path5<File.join>")
      assert_includes context.payloads, stub_payload(:body, "/etc/passwd", "path6<File.join>")
    end

    test "query parameter names are extracted as payloads" do
      context = build_context_for("/path?a=1&b=2&c=3")

      assert_includes context.payloads, stub_payload(:query, "a", "a")
      assert_includes context.payloads, stub_payload(:query, "b", "b")
      assert_includes context.payloads, stub_payload(:query, "c", "c")
    end

    test "header names are extracted as payloads" do
      context = build_context_for("/path", {
        "HTTP_ACCEPT" => "application/json",
        "HTTP_USER_AGENT" => "Test/UA"
      })

      assert_includes context.payloads, stub_payload(:header, "Accept", "Accept")
      assert_includes context.payloads, stub_payload(:header, "User-Agent", "User-Agent")
    end

    test "cookie names are extracted as payloads" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => "c1=foo; c2=bar; c3=baz"
      })

      assert_includes context.payloads, stub_payload(:cookie, "c1", "c1")
      assert_includes context.payloads, stub_payload(:cookie, "c2", "c2")
      assert_includes context.payloads, stub_payload(:cookie, "c3", "c3")
    end

    test "body keys are extracted as payloads from form-encoded bodies" do
      context = build_context_for("/example/path", {
        :method => "POST",
        :input => "username=mallory&role=admin",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })

      assert_includes context.payloads, stub_payload(:body, "username", "username")
      assert_includes context.payloads, stub_payload(:body, "role", "role")
    end

    test "body keys are extracted as payloads from multipart-encoded bodies" do
      context = build_context_for("/example/path", multipart_env("username" => "mallory", "role" => "admin"))

      assert_includes context.payloads, stub_payload(:body, "username", "username")
      assert_includes context.payloads, stub_payload(:body, "role", "role")
    end

    test "nested keys are extracted as payloads at every level" do
      context = build_context_for("/path?a[n]=1", {
        method: "POST",
        params: {y: {w: {i: "6"}}}
      })

      assert_includes context.payloads, stub_payload(:query, "a", "a")
      assert_includes context.payloads, stub_payload(:query, "n", "a.n")
      assert_includes context.payloads, stub_payload(:body, "y", "y")
      assert_includes context.payloads, stub_payload(:body, "w", "y.w")
      assert_includes context.payloads, stub_payload(:body, "i", "y.w.i")
    end

    test "the context can store metadata" do
      context = build_context_for("/path")

      context["foo"] = "bar"
      assert_equal "bar", context["foo"]
    end

    test "#scanning? is false by default" do
      context = build_context_for("/path")
      refute context.scanning?
    end

    test "#request_bypassed? is nil by default" do
      context = build_context_for("/path")
      assert_nil context.request_bypassed?
    end

    test "#protection_disabled? is false by default" do
      context = build_context_for("/path")
      refute context.protection_disabled?
    end

    test "#idor_protection_enabled? is false by default" do
      context = build_context_for("/path")
      refute context.idor_protection_enabled?
    end
  end

  class RackRequestTest < ActiveSupport::TestCase
    include GenericTests

    setup do
      Aikido::Zen.config.request_builder = Aikido::Zen::Context::RACK_REQUEST_BUILDER
      Aikido::Zen.config.harden = false
    end

    def env_for(path, env = {})
      Rack::MockRequest.env_for(path, env)
    end

    def build_context_for(path, env = {})
      env = env_for(path, env)
      Aikido::Zen::Context.from_rack_env(env)
    end

    def stub_payload(source, value, path)
      Aikido::Zen::Payload.new(value, source, path)
    end

    test "the Rack::Request builder wraps a Rack::Request-based Context" do
      context = Aikido::Zen::Context.from_rack_env({})
      assert_kind_of Aikido::Zen::Request, context.request
      assert_kind_of Rack::Request, context.request.__getobj__
    end

    test "JSON bodies are not parsed by the Rack implementation" do
      context = build_context_for("/path?a=1", {
        :method => "POST",
        :input => %({"test":"value","nested":{"hash":"data"},"array":[1, 2, 3]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_empty context.payloads.select { |payload| payload.source == :body }
    end

    test "form bodies are extracted without overriding a later replacement of the body by middleware" do
      env = Rack::MockRequest.env_for("/path", {
        :method => "POST",
        :input => "username=mallory&role=admin",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })
      Aikido::Zen::Context.from_rack_env(env).payloads

      env["rack.input"] = StringIO.new("username=mallory")

      assert_equal({"username" => "mallory"}, Rack::Request.new(env).POST)
    end

    test "route params are empty on the base case as they are framework dependent" do
      context = build_context_for("/some/path")

      assert_empty context.payloads.select { |payload| payload.source == :route }
    end

    test "subdomain params are empty for the base case as Rack doesn't provide tooling for this" do
      context = build_context_for("https://test.example.com/path")

      assert_empty context.payloads.select { |payload| payload.source == :subdomain }
    end
  end

  class RailsRequestTest < ActiveSupport::TestCase
    include GenericTests

    setup do
      Aikido::Zen.config.request_builder = Aikido::Zen::Context::RAILS_REQUEST_BUILDER
      Aikido::Zen.config.harden = false
    end

    def env_for(path, env = {})
      env = Rack::MockRequest.env_for(path, env)
      Rails.application.env_config.merge(env)
    end

    def build_cookie_header(&block)
      req = ActionDispatch::Request.new(env_for("/", {}))
      block.call(req.cookie_jar)
      req.cookie_jar.to_header
    end

    def build_context_for(path, env = {})
      env = env_for(path, env)
      Aikido::Zen::Context.from_rack_env(env)
    end

    def stub_payload(source, value, path)
      Aikido::Zen::Payload.new(value, source, path)
    end

    test "the Rails builder wraps a ActionDispatch::Request" do
      context = Aikido::Zen::Context.from_rack_env({})
      assert_kind_of Aikido::Zen::Request, context.request
      assert_kind_of ActionDispatch::Request, context.request.__getobj__
    end

    test "body payloads are read from JSON-encoded bodies" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"key":"value","hash":{"first":0,"key":"value","last":2.0},"array":["1", "two", 3, "iv"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_includes context.payloads, stub_payload(:body, "value", "key")

      assert_includes context.payloads, stub_payload(:body, "value", "hash.key")

      # Values must be strings to be extracted
      refute_includes context.payloads, stub_payload(:body, 0, "hash.first")
      refute_includes context.payloads, stub_payload(:body, 2.0, "hash.last")

      assert_includes context.payloads, stub_payload(:body, "1", "array.0")
      assert_includes context.payloads, stub_payload(:body, "two", "array.1")
      assert_includes context.payloads, stub_payload(:body, "iv", "array.3")

      # Values must be strings to be extracted
      refute_includes context.payloads, stub_payload(:body, 3, "array.2")
    end

    test "body keys are extracted as payloads from JSON-encoded bodies" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"key":"value","hash":{"first":0,"inner":"value"},"array":["1"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_includes context.payloads, stub_payload(:body, "key", "key")
      assert_includes context.payloads, stub_payload(:body, "hash", "hash")
      assert_includes context.payloads, stub_payload(:body, "first", "hash.first")
      assert_includes context.payloads, stub_payload(:body, "inner", "hash.inner")
      assert_includes context.payloads, stub_payload(:body, "array", "array")
    end

    test "body payloads are not read from JSON-encoded bodies that cannot be parsed" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"test":"value","nested":{"hash":"data"},"array":[1, 2, 3),
        "CONTENT_TYPE" => "application/json"
      })

      payloads = nil

      assert_silent do
        # Suppress message from the ActionDispatch::Http::Parameters#log_parse_error_once private method
        original_stderr = $stderr
        $stderr = StringIO.new

        payloads = context.payloads
      ensure
        $stderr = original_stderr
      end

      assert payloads.none? { |payload| payload.source == :body }
    end

    test "relative path arrays in body payloads read from JSON-encoded bodies are joined for File.join" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"path":["..", "..", "..", "etc", "passwd"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_includes context.payloads, stub_payload(:body, "../../../etc/passwd", "path<File.join>")
    end

    test "absolute path arrays in body payloads read from JSON-encoded bodies are joined for File.join" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"path1": ["/", "etc", "passwd"], "path2": ["", "etc", "passwd"], "path3": ["/etc", "passwd"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_includes context.payloads, stub_payload(:body, "/etc/passwd", "path1<File.join>")
      assert_includes context.payloads, stub_payload(:body, "/etc/passwd", "path2<File.join>")
      assert_includes context.payloads, stub_payload(:body, "/etc/passwd", "path3<File.join>")
    end

    test "route payloads are read from the data extracted by the router" do
      router = MockedRailsRouter.build do
        match "/example/:resource(/:id)(.:format)",
          via: [:get, :post],
          to: "example#test"
      end

      env = env_for("/example/user/23.json")
      env = router.process(env)
      context = Aikido::Zen::Context.from_rack_env(env)

      assert_includes context.payloads, stub_payload(:route, "user", "resource")
      assert_includes context.payloads, stub_payload(:route, "23", "id")
      assert_includes context.payloads, stub_payload(:route, "json", "format")
      assert_includes context.payloads, stub_payload(:route, "example", "controller")
      assert_includes context.payloads, stub_payload(:route, "test", "action")
    end

    test "cookie params includes the plain-text values of encrypted cookies" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => build_cookie_header { |cookies|
          cookies["c1"] = {value: "foo", expires: Date.tomorrow}
          cookies.encrypted["c2"] = "encrypted_value"
          cookies["c3"] = "baz"
        }
      })

      assert_includes context.payloads, stub_payload(:cookie, "foo", "c1")
      assert_includes context.payloads, stub_payload(:cookie, "encrypted_value", "c2")
      assert_includes context.payloads, stub_payload(:cookie, "baz", "c3")
    end

    test "cookie params includes the plain-text values of signed cookies" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => build_cookie_header { |cookies|
          cookies["c1"] = {value: "foo", expires: Date.tomorrow}
          cookies.signed["c2"] = "signed_value"
          cookies["c3"] = "baz"
        }
      })

      assert_includes context.payloads, stub_payload(:cookie, "foo", "c1")
      assert_includes context.payloads, stub_payload(:cookie, "signed_value", "c2")
      assert_includes context.payloads, stub_payload(:cookie, "baz", "c3")
    end

    test "subdomain params are sourced from the request URL, based on the configured TLD length" do
      with_tld_length 1 do
        context = build_context_for("https://test.domain.example.com/path")

        assert_includes context.payloads, stub_payload(:subdomain, "test", "0")
        assert_includes context.payloads, stub_payload(:subdomain, "domain", "1")
      end

      with_tld_length 2 do
        context = build_context_for("https://test.domain.example.com/path")

        assert_includes context.payloads, stub_payload(:subdomain, "test", "0")
        refute_includes context.payloads, stub_payload(:subdomain, "domain", "1")
      end

      with_tld_length 3 do
        context = build_context_for("https://test.domain.example.com/path")

        assert_empty context.payloads.select { |payload| payload.source == :subdomain }
      end
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
