# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::ContextTest < ActiveSupport::TestCase
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

  test "context links to a framework-specific request object" do
    env = {}

    framework_request = DummyRequest.new(env)
    context = Aikido::Zen::Context.new(framework_request)

    assert_equal framework_request, context.request
  end

  test "inputs are the keys and values of all the sources" do
    context = Aikido::Zen::Context.new(DummyRequest.new({})) {
      {query: {"a" => "q"}, body: {"b" => "x"}}
    }

    assert_equal %w[a q b x], context.each_input.to_a
  end

  test "inputs are the keys and values of the named sources only" do
    context = Aikido::Zen::Context.new(DummyRequest.new({})) {
      {query: {"a" => "q"}, body: {"b" => "x"}, header: {"c" => "h"}}
    }

    assert_equal %w[a q], context.each_input(:query).to_a
    assert_equal %w[b x c h], context.each_input(:body, :header).to_a
  end

  test "inputs of a source are the same whether or not other sources were read" do
    context = Aikido::Zen::Context.new(DummyRequest.new({})) {
      {query: {"a" => "same", "b" => "q"}, body: {"c" => "same", "d" => "other"}}
    }

    assert_equal %w[a same b q], context.each_input(:query).to_a

    context.each_input.to_a

    assert_equal %w[a same b q], context.each_input(:query).to_a
  end

  test "inputs of a source are unique" do
    context = Aikido::Zen::Context.new(DummyRequest.new({})) {
      {query: {"a" => "same", "b" => "same"}}
    }

    assert_equal %w[a same b], context.each_input.to_a
  end

  test "inputs of a source that does not exist are empty" do
    context = Aikido::Zen::Context.new(DummyRequest.new({})) { {body: {"a" => "b"}} }

    assert_empty context.each_input(:query).to_a
  end

  test "inputs of a source are extracted once" do
    source = Minitest::Mock.new
    source.expect(:to_hash, {"a" => "b"})

    context = Aikido::Zen::Context.new(DummyRequest.new({})) { {query: source} }

    2.times { context.each_input.to_a }

    assert_mock source
  end

  test "inputs of a source are extracted once, whether read by name or with all the sources" do
    source = Minitest::Mock.new
    source.expect(:to_hash, {"a" => "b"})

    context = Aikido::Zen::Context.new(DummyRequest.new({})) { {query: source} }

    context.each_input(:query).to_a
    context.each_input.to_a

    assert_mock source
  end

  test "inputs of a source are not cached when extracting them fails" do
    source = Minitest::Mock.new
    source.expect(:to_hash, nil) { raise "boom" }
    source.expect(:to_hash, {"a" => "b"})

    context = Aikido::Zen::Context.new(DummyRequest.new({})) { {query: source} }

    assert_raise(RuntimeError) { context.each_input(:query).to_a }

    assert_equal %w[a b], context.each_input(:query).to_a

    assert_mock source
  end

  test "the sources are built once, for inputs and payloads" do
    calls = 0
    context = Aikido::Zen::Context.new(DummyRequest.new({})) {
      calls += 1
      {query: {"a" => "b"}, body: {"c" => "d"}}
    }

    context.each_input(:query).to_a
    context.each_input.to_a
    context.payload("d")

    assert_equal 1, calls
  end

  test "payload is for the first occurrence of an input" do
    context = Aikido::Zen::Context.new(DummyRequest.new({})) {
      {query: {"a" => "same"}, body: {"b" => "same", "c" => {"d" => "only"}}}
    }

    assert_equal Aikido::Zen::Payload.new("same", :query, "a"), context.payload("same")
    assert_equal Aikido::Zen::Payload.new("only", :body, "c.d"), context.payload("only")
    assert_equal Aikido::Zen::Payload.new("b", :body, "b"), context.payload("b")
  end

  test "payload is nil for a value that is not an input" do
    context = Aikido::Zen::Context.new(DummyRequest.new({})) { {query: {"a" => "b"}} }

    assert_nil context.payload("missing")
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

      assert_equal stub_payload(:query, "1", "a"), context.payload("1")
      assert_equal stub_payload(:query, "2", "b"), context.payload("2")
      assert_equal stub_payload(:query, "3", "c"), context.payload("3")
    end

    test "body payloads are read from the request body" do
      context = build_context_for("/example/path?a=1", {
        method: "POST",
        params: {b: "2", c: "3"}
      })

      assert_equal stub_payload(:body, "2", "b"), context.payload("2")
      assert_equal stub_payload(:body, "3", "c"), context.payload("3")
    end

    test "form bodies are extracted without consuming the request body" do
      input = StringIO.new("username=mallory&role=admin")
      context = build_context_for("/example/path", {
        :method => "POST",
        :input => input,
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })

      assert_equal stub_payload(:body, "admin", "role"), context.payload("admin")
      assert_equal "username=mallory&role=admin", input.read
    end

    test "form bodies are extracted without consuming a request body that cannot be rewound" do
      env = env_for("/example/path", {
        :method => "POST",
        :input => NonRewindableInput.new("username=mallory&role=admin"),
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })
      context = Aikido::Zen::Context.from_rack_env(env)

      assert_equal stub_payload(:body, "admin", "role"), context.payload("admin")
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

      assert_equal stub_payload(:body, "admin", "role"), context.payload("admin")
      assert_equal "username=mallory&role=admin", env["rack.input"].read
    end

    test "form bodies are extracted without caching the parsed form on the request env" do
      env = env_for("/example/path", {
        :method => "POST",
        :input => "username=mallory&role=admin",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })
      context = Aikido::Zen::Context.from_rack_env(env)
      context.each_input.to_a

      assert_nil context.request.env["rack.request.form_hash"]
      assert_nil context.request.env["rack.request.form_pairs"]
    end

    test "body payloads are read from multipart-encoded bodies" do
      context = build_context_for("/example/path", multipart_env("username" => "mallory", "role" => "admin"))

      assert_equal stub_payload(:body, "mallory", "username"), context.payload("mallory")
      assert_equal stub_payload(:body, "admin", "role"), context.payload("admin")
    end

    test "header params are sourced from the normalized headers" do
      context = build_context_for("/path", {
        "HTTP_ACCEPT" => "application/json",
        "HTTP_USER_AGENT" => "Test/UA",
        "HTTP_AUTHORIZATION" => "Token S3CR37"
      })

      assert_equal stub_payload(:header, "application/json", "Accept"), context.payload("application/json")
      assert_equal stub_payload(:header, "Test/UA", "User-Agent"), context.payload("Test/UA")
      assert_equal stub_payload(:header, "Token S3CR37", "Authorization"), context.payload("Token S3CR37")
    end

    test "cookie params are sourced from the Cookie header" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => "c1=foo; c2=bar; c3=baz"
      })

      assert_equal stub_payload(:cookie, "foo", "c1"), context.payload("foo")
      assert_equal stub_payload(:cookie, "bar", "c2"), context.payload("bar")
      assert_equal stub_payload(:cookie, "baz", "c3"), context.payload("baz")
    end

    test "URL-decoded variants of double-encoded query values are extracted" do
      context = build_context_for("/path?q=%2527+OR+1")

      assert_equal stub_payload(:query, "%27 OR 1", "q"), context.payload("%27 OR 1")
      assert_equal stub_payload(:query, "' OR 1", "q"), context.payload("' OR 1")
    end

    test "URL-decoded variants of header values are extracted" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "%27+OR+1"})

      assert_equal stub_payload(:header, "%27+OR+1", "X-Test"), context.payload("%27+OR+1")
      assert_equal stub_payload(:header, "'+OR+1", "X-Test"), context.payload("'+OR+1")
    end

    test "undecoded values are extracted alongside their URL-decoded variants" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%2520b"})

      assert_equal stub_payload(:header, "a%2520b", "X-Test"), context.payload("a%2520b")
      assert_equal stub_payload(:header, "a%20b", "X-Test"), context.payload("a%20b")
      assert_equal stub_payload(:header, "a b", "X-Test"), context.payload("a b")
    end

    test "values are URL-decoded repeatedly" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%252520b"})

      assert_equal stub_payload(:header, "a%2520b", "X-Test"), context.payload("a%2520b")
      assert_equal stub_payload(:header, "a%20b", "X-Test"), context.payload("a%20b")
      assert_equal stub_payload(:header, "a b", "X-Test"), context.payload("a b")
    end

    test "values are URL-decoded at most five times" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%252525252520b"})

      assert_equal stub_payload(:header, "a%20b", "X-Test"), context.payload("a%20b")
      assert_nil context.payload("a b")
    end

    test "URL-decoding does not turn plus signs into spaces" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a+b%20c"})

      assert_equal stub_payload(:header, "a+b c", "X-Test"), context.payload("a+b c")
      assert_nil context.payload("a b c")
    end

    test "invalid percent-encoded sequences are left as they are" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "%27%zz%2"})

      assert_equal stub_payload(:header, "%27%zz%2", "X-Test"), context.payload("%27%zz%2")
      assert_equal stub_payload(:header, "'%zz%2", "X-Test"), context.payload("'%zz%2")
    end

    test "URL-decoded variants that are not valid UTF-8 are extracted with invalid bytes replaced" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "a%ffb"})

      assert_equal stub_payload(:header, "a%ffb", "X-Test"), context.payload("a%ffb")
      assert_equal stub_payload(:header, "a�b", "X-Test"), context.payload("a�b")
    end

    test "binary strings are extracted as UTF-8" do
      context = build_context_for("/path", {"HTTP_X_TEST" => "caf\xC3\xA9".b})

      assert_equal stub_payload(:header, "café", "X-Test"), context.payload("café")
    end

    test "keys are not URL-decoded" do
      context = build_context_for("/path", {"HTTP_COOKIE" => "a%2520b=1"})

      assert_equal stub_payload(:cookie, "a%2520b", "a%2520b"), context.payload("a%2520b")
      assert_nil context.payload("a b")
    end

    test "the path for complex parameter structures is tracked correctly" do
      context = build_context_for("/path?a[n]=1&a[m]=2&b[]=3&b[]=4", {
        method: "POST",
        params: {x: ["5", "6"], y: {u: "7", v: "8", w: {i: "9", j: "10"}}}
      })

      assert_equal stub_payload(:query, "1", "a.n"), context.payload("1")
      assert_equal stub_payload(:query, "2", "a.m"), context.payload("2")
      assert_equal stub_payload(:query, "3", "b.0"), context.payload("3")
      assert_equal stub_payload(:query, "4", "b.1"), context.payload("4")

      assert_equal stub_payload(:body, "5", "x.0"), context.payload("5")
      assert_equal stub_payload(:body, "6", "x.1"), context.payload("6")

      assert_equal stub_payload(:body, "7", "y.u"), context.payload("7")
      assert_equal stub_payload(:body, "8", "y.v"), context.payload("8")
      assert_equal stub_payload(:body, "9", "y.w.i"), context.payload("9")
      assert_equal stub_payload(:body, "10", "y.w.j"), context.payload("10")
    end

    test "relative path arrays in complex parameter structures are joined for File.join" do
      context = build_context_for("/path?path1[]=..&path1[]=..&path1[]=..&path1[]=etc&path1[]=passwd", {
        method: "POST",
        params: {path2: ["..", "..", "..", "etc", "shadow"]}
      })

      assert_equal stub_payload(:query, "../../../etc/passwd", "path1<File.join>"), context.payload("../../../etc/passwd")

      assert_equal stub_payload(:body, "../../../etc/shadow", "path2<File.join>"), context.payload("../../../etc/shadow")
    end

    test "absolute path arrays in complex parameter structures are joined for File.join" do
      context = build_context_for("/path?path1[]=&path1[]=etc&path1[]=passwd&path2[]=/&path2[]=etc&path2[]=shadow&path3[]=/etc&path3[]=hosts", {
        method: "POST",
        params: {path4: ["/", "etc", "group"], path5: ["", "etc", "hostname"], path6: ["/etc", "fstab"]}
      })

      assert_equal stub_payload(:query, "/etc/passwd", "path1<File.join>"), context.payload("/etc/passwd")
      assert_equal stub_payload(:query, "/etc/shadow", "path2<File.join>"), context.payload("/etc/shadow")
      assert_equal stub_payload(:query, "/etc/hosts", "path3<File.join>"), context.payload("/etc/hosts")

      assert_equal stub_payload(:body, "/etc/group", "path4<File.join>"), context.payload("/etc/group")
      assert_equal stub_payload(:body, "/etc/hostname", "path5<File.join>"), context.payload("/etc/hostname")
      assert_equal stub_payload(:body, "/etc/fstab", "path6<File.join>"), context.payload("/etc/fstab")
    end

    test "query parameter names are extracted as payloads" do
      context = build_context_for("/path?a=1&b=2&c=3")

      assert_equal stub_payload(:query, "a", "a"), context.payload("a")
      assert_equal stub_payload(:query, "b", "b"), context.payload("b")
      assert_equal stub_payload(:query, "c", "c"), context.payload("c")
    end

    test "header names are extracted as payloads" do
      context = build_context_for("/path", {
        "HTTP_ACCEPT" => "application/json",
        "HTTP_USER_AGENT" => "Test/UA"
      })

      assert_equal stub_payload(:header, "Accept", "Accept"), context.payload("Accept")
      assert_equal stub_payload(:header, "User-Agent", "User-Agent"), context.payload("User-Agent")
    end

    test "cookie names are extracted as payloads" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => "c1=foo; c2=bar; c3=baz"
      })

      assert_equal stub_payload(:cookie, "c1", "c1"), context.payload("c1")
      assert_equal stub_payload(:cookie, "c2", "c2"), context.payload("c2")
      assert_equal stub_payload(:cookie, "c3", "c3"), context.payload("c3")
    end

    test "body keys are extracted as payloads from form-encoded bodies" do
      context = build_context_for("/example/path", {
        :method => "POST",
        :input => "username=mallory&role=admin",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })

      assert_equal stub_payload(:body, "username", "username"), context.payload("username")
      assert_equal stub_payload(:body, "role", "role"), context.payload("role")
    end

    test "body keys are extracted as payloads from multipart-encoded bodies" do
      context = build_context_for("/example/path", multipart_env("username" => "mallory", "role" => "admin"))

      assert_equal stub_payload(:body, "username", "username"), context.payload("username")
      assert_equal stub_payload(:body, "role", "role"), context.payload("role")
    end

    test "nested keys are extracted as payloads at every level" do
      context = build_context_for("/path?a[n]=1", {
        method: "POST",
        params: {y: {w: {i: "6"}}}
      })

      assert_equal stub_payload(:query, "a", "a"), context.payload("a")
      assert_equal stub_payload(:query, "n", "a.n"), context.payload("n")
      assert_equal stub_payload(:body, "y", "y"), context.payload("y")
      assert_equal stub_payload(:body, "w", "y.w"), context.payload("w")
      assert_equal stub_payload(:body, "i", "y.w.i"), context.payload("i")
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

      assert_empty context.each_input(:body).to_a
    end

    test "form bodies are extracted without overriding a later replacement of the body by middleware" do
      env = Rack::MockRequest.env_for("/path", {
        :method => "POST",
        :input => "username=mallory&role=admin",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      })
      Aikido::Zen::Context.from_rack_env(env).each_input.to_a

      env["rack.input"] = StringIO.new("username=mallory")

      assert_equal({"username" => "mallory"}, Rack::Request.new(env).POST)
    end

    test "route params are empty on the base case as they are framework dependent" do
      context = build_context_for("/some/path")

      assert_empty context.each_input(:route).to_a
    end

    test "subdomain params are empty for the base case as Rack doesn't provide tooling for this" do
      context = build_context_for("https://test.example.com/path")

      assert_empty context.each_input(:subdomain).to_a
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

    test "inputs and payloads are read again after the request is updated" do
      context = build_context_for("/path?a=first")

      assert_includes context.each_input, "first"
      assert_equal stub_payload(:query, "first", "a"), context.payload("first")

      context.update_request(ActionDispatch::Request.new(env_for("/path?a=second")))

      assert_includes context.each_input, "second"
      refute_includes context.each_input, "first"
      assert_equal stub_payload(:query, "second", "a"), context.payload("second")
      assert_nil context.payload("first")
    end

    test "the Rails builder wraps a ActionDispatch::Request" do
      context = Aikido::Zen::Context.from_rack_env({})
      assert_kind_of Aikido::Zen::Request, context.request
      assert_kind_of ActionDispatch::Request, context.request.__getobj__
    end

    test "body payloads are read from JSON-encoded bodies" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"key":"value","hash":{"first":0,"key":"other","last":2.0},"array":["1", "two", 3, "iv"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_equal stub_payload(:body, "value", "key"), context.payload("value")

      assert_equal stub_payload(:body, "other", "hash.key"), context.payload("other")

      # Values must be strings to be extracted
      assert_nil context.payload("0")
      assert_nil context.payload("2.0")

      assert_equal stub_payload(:body, "1", "array.0"), context.payload("1")
      assert_equal stub_payload(:body, "two", "array.1"), context.payload("two")
      assert_equal stub_payload(:body, "iv", "array.3"), context.payload("iv")

      # Values must be strings to be extracted
      assert_nil context.payload("3")
    end

    test "body keys are extracted as payloads from JSON-encoded bodies" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"key":"value","hash":{"first":0,"inner":"value"},"array":["1"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_equal stub_payload(:body, "key", "key"), context.payload("key")
      assert_equal stub_payload(:body, "hash", "hash"), context.payload("hash")
      assert_equal stub_payload(:body, "first", "hash.first"), context.payload("first")
      assert_equal stub_payload(:body, "inner", "hash.inner"), context.payload("inner")
      assert_equal stub_payload(:body, "array", "array"), context.payload("array")
    end

    test "body payloads are not read from JSON-encoded bodies that cannot be parsed" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"test":"value","nested":{"hash":"data"},"array":[1, 2, 3),
        "CONTENT_TYPE" => "application/json"
      })

      inputs = nil

      assert_silent do
        # Suppress message from the ActionDispatch::Http::Parameters#log_parse_error_once private method
        original_stderr = $stderr
        $stderr = StringIO.new

        inputs = context.each_input(:body).to_a
      ensure
        $stderr = original_stderr
      end

      assert_empty inputs
    end

    test "relative path arrays in body payloads read from JSON-encoded bodies are joined for File.join" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"path":["..", "..", "..", "etc", "passwd"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_equal stub_payload(:body, "../../../etc/passwd", "path<File.join>"), context.payload("../../../etc/passwd")
    end

    test "absolute path arrays in body payloads read from JSON-encoded bodies are joined for File.join" do
      context = build_context_for("/example", {
        :method => "POST",
        :input => %({"path1": ["/", "etc", "passwd"], "path2": ["", "etc", "shadow"], "path3": ["/etc", "hosts"]}),
        "CONTENT_TYPE" => "application/json"
      })

      assert_equal stub_payload(:body, "/etc/passwd", "path1<File.join>"), context.payload("/etc/passwd")
      assert_equal stub_payload(:body, "/etc/shadow", "path2<File.join>"), context.payload("/etc/shadow")
      assert_equal stub_payload(:body, "/etc/hosts", "path3<File.join>"), context.payload("/etc/hosts")
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

      assert_equal stub_payload(:route, "user", "resource"), context.payload("user")
      assert_equal stub_payload(:route, "23", "id"), context.payload("23")
      assert_equal stub_payload(:route, "json", "format"), context.payload("json")
      assert_equal stub_payload(:route, "example", "controller"), context.payload("example")
      assert_equal stub_payload(:route, "test", "action"), context.payload("test")
    end

    test "cookie params includes the plain-text values of encrypted cookies" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => build_cookie_header { |cookies|
          cookies["c1"] = {value: "foo", expires: Date.tomorrow}
          cookies.encrypted["c2"] = "encrypted_value"
          cookies["c3"] = "baz"
        }
      })

      assert_equal stub_payload(:cookie, "foo", "c1"), context.payload("foo")
      assert_equal stub_payload(:cookie, "encrypted_value", "c2"), context.payload("encrypted_value")
      assert_equal stub_payload(:cookie, "baz", "c3"), context.payload("baz")
    end

    test "cookie params includes the plain-text values of signed cookies" do
      context = build_context_for("/path", {
        "HTTP_COOKIE" => build_cookie_header { |cookies|
          cookies["c1"] = {value: "foo", expires: Date.tomorrow}
          cookies.signed["c2"] = "signed_value"
          cookies["c3"] = "baz"
        }
      })

      assert_equal stub_payload(:cookie, "foo", "c1"), context.payload("foo")
      assert_equal stub_payload(:cookie, "signed_value", "c2"), context.payload("signed_value")
      assert_equal stub_payload(:cookie, "baz", "c3"), context.payload("baz")
    end

    test "subdomain params are sourced from the request URL, based on the configured TLD length" do
      with_tld_length 1 do
        context = build_context_for("https://test.domain.example.com/path")

        assert_equal stub_payload(:subdomain, "test", "0"), context.payload("test")
        assert_equal stub_payload(:subdomain, "domain", "1"), context.payload("domain")
      end

      with_tld_length 2 do
        context = build_context_for("https://test.domain.example.com/path")

        assert_equal stub_payload(:subdomain, "test", "0"), context.payload("test")
        assert_nil context.payload("domain")
      end

      with_tld_length 3 do
        context = build_context_for("https://test.domain.example.com/path")

        assert_empty context.each_input(:subdomain).to_a
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
