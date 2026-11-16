# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::PayloadExtractorTest < ActiveSupport::TestCase
  include JWTHelpers

  def extract(sources)
    Aikido::Zen::PayloadExtractor.new.extract(sources)
  end

  def jwt_payloads(value, source: :body)
    extract({source => {"token" => value}})
  end

  def payloads_for(query, harden: false)
    Aikido::Zen.config.harden = harden

    extract({query: query})
  end

  def assert_valid_utf8(payloads)
    refute_empty payloads
    payloads.each do |payload|
      [payload.value, payload.path].each do |string|
        assert_equal Encoding::UTF_8, string.encoding, payload.inspect
        assert string.valid_encoding?, payload.inspect
      end
    end
  end

  test "string values are extracted as valid UTF-8" do
    payloads = payloads_for({"a" => "x\xFFy".b, "b" => "caf\xC3\xA9".b})

    assert_includes payloads, Aikido::Zen::Payload.new("x�y", :query, "a")
    assert_includes payloads, Aikido::Zen::Payload.new("café", :query, "b")
    assert_valid_utf8 payloads
  end

  test "values that are not strings are not extracted" do
    payloads = payloads_for({
      "h" => {"n" => nil, "i" => 1, "f" => 1.5, "t" => true, "s" => :sym, "str" => "kept"},
      "a" => [nil, 1, 1.5, true, :sym, "kept too"]
    })

    assert_equal %w[h n i f t s str kept a] + ["kept too"], payloads.map(&:value)
  end

  test "array values are extracted as valid UTF-8" do
    payloads = payloads_for({"p" => ["x\xFFy".b, "caf\xC3\xA9".b]})

    assert_includes payloads, Aikido::Zen::Payload.new("x�y", :query, "p.0")
    assert_includes payloads, Aikido::Zen::Payload.new("café", :query, "p.1")
    assert_valid_utf8 payloads
  end

  test "array values are extracted with their indexes in their paths" do
    root = payloads_for(["r", ["s"]])
    nested = payloads_for({"p" => ["a", ["b"]]})

    assert_equal [["r", "0"], ["s", "1.0"]], root.map { |payload| [payload.value, payload.path] }
    assert_equal [["p", "p"], ["a", "p.0"], ["b", "p.1.0"]], nested.map { |payload| [payload.value, payload.path] }
  end

  test "array values are joined for File.join as valid UTF-8" do
    payloads = payloads_for({"p" => ["caf\xC3\xA9".b, "..", "..", "etc", "passwd"]})

    assert_includes payloads, Aikido::Zen::Payload.new("café/../../etc/passwd", :query, "p<File.join>")
    assert_valid_utf8 payloads
  end

  test "array values are not joined for File.join when they are not all strings" do
    payloads = payloads_for({"p" => ["..", 1, "etc"]})

    refute_includes payloads.map(&:path), "p<File.join>"
    assert_includes payloads, Aikido::Zen::Payload.new("..", :query, "p.0")
    assert_includes payloads, Aikido::Zen::Payload.new("etc", :query, "p.2")
  end

  test "array values are not joined for File.join when hardened" do
    payloads = payloads_for({"p" => ["..", "..", "etc", "passwd"]}, harden: true)

    refute_includes payloads.map(&:path), "p<File.join>"
    assert_includes payloads, Aikido::Zen::Payload.new("passwd", :query, "p.3")
  end

  test "hash values are extracted with their keys in their paths" do
    payloads = payloads_for({"a" => {"b" => "v", "c" => {"d" => "w"}}})

    assert_equal [["a", "a"], ["b", "a.b"], ["v", "a.b"], ["c", "a.c"], ["d", "a.c.d"], ["w", "a.c.d"]],
      payloads.map { |payload| [payload.value, payload.path] }
  end

  test "hash-like values are extracted like hashes" do
    with_indifferent_access = ActiveSupport::HashWithIndifferentAccess.new("a" => {"b" => "v"})
    responds_to_hash = Minitest::Mock.new
    responds_to_hash.expect(:to_hash, {"b" => "w"})

    assert_equal payloads_for({"a" => {"b" => "v"}}).to_a, payloads_for(with_indifferent_access).to_a
    assert_equal [["x", "x"], ["b", "x.b"], ["w", "x.b"]],
      payloads_for({"x" => responds_to_hash}).map { |payload| [payload.value, payload.path] }
    assert_mock responds_to_hash
  end

  test "keys are extracted as valid UTF-8" do
    payloads = payloads_for({"x\xFFy".b => "1", "caf\xC3\xA9".b => "2"})

    assert_includes payloads.map(&:value), "x�y"
    assert_includes payloads.map(&:value), "café"
    assert_valid_utf8 payloads
  end

  test "keys with non-ASCII bytes in binary strings are extracted as valid UTF-8 under keys with non-ASCII characters" do
    payloads = payloads_for({"café" => {"k\xC3\xA9".b => "v", "bad\xFF".b => "w"}})

    assert_includes payloads, Aikido::Zen::Payload.new("v", :query, "café.ké")
    assert_includes payloads, Aikido::Zen::Payload.new("w", :query, "café.bad�")
    assert_valid_utf8 payloads

    # Deeper

    payloads = payloads_for({"id" => {"k\xC3\xA9".b => {"k\xC3\xA9".b => "deep"}}})

    assert_includes payloads, Aikido::Zen::Payload.new("deep", :query, "id.ké.ké")
    assert_valid_utf8 payloads
  end

  test "paths are extracted as valid UTF-8" do
    payloads = payloads_for({"x\xFFy".b => {"caf\xC3\xA9".b => ["z"]}, "ok" => "v"})

    assert_includes payloads, Aikido::Zen::Payload.new("z", :query, "x�y.café.0")
    assert_includes payloads, Aikido::Zen::Payload.new("v", :query, "ok")
    assert_valid_utf8 payloads
  end

  test "paths are extracted as valid UTF-8 when they have no string keys" do
    assert_valid_utf8 payloads_for("top")
    assert_valid_utf8 payloads_for(["a", ["b"]])
    assert_valid_utf8 payloads_for({7 => "x", nil => "y", :sym => "z"})
  end

  test "paths are built from string, symbol, integer and nil keys and from array indexes" do
    payloads = payloads_for({nil => "n", :sym => "s", 7 => {"k" => "v"}, "a" => [["x", {"b" => [1, "deep"]}], "y"]})

    paths = payloads.to_h { |payload| [payload.value, payload.path] }

    assert_equal "", paths["n"]
    assert_equal "sym", paths["s"]
    assert_equal "7.k", paths["v"]
    assert_equal "a.0.0", paths["x"]
    assert_equal "a.0.1.b.1", paths["deep"]
    assert_equal "a.1", paths["y"]
  end

  test "paths are built from empty keys and the values under them are extracted" do
    payloads = payloads_for({"" => {"k" => "v"}, "a" => {"" => {"b" => "w"}}})

    paths = payloads.to_h { |payload| [payload.value, payload.path] }

    assert_equal ".k", paths["v"]
    assert_equal "a..b", paths["w"]
  end

  test "payload extraction does not recurse past the configured maximum depth" do
    Aikido::Zen.config.extract_payloads_max_depth = 2

    data = {"a" => {"b" => "kept at the depth limit", "c" => {"d" => "dropped past the depth limit"}}}
    payloads = extract({body: data})

    assert_includes payloads, Aikido::Zen::Payload.new("kept at the depth limit", :body, "a.b")
    refute_includes payloads, Aikido::Zen::Payload.new("dropped past the depth limit", :body, "a.c.d")
  end

  test "payload extraction caps recursion depth to prevent a stack overflow" do
    data = "leaf"
    10_000.times { data = {"k" => data} }

    assert_nothing_raised { extract({body: data}) }
  end

  test "the File.join special case for arrays does not stack overflow on deeply nested arrays" do
    Aikido::Zen.config.harden = false

    data = "leaf"
    200_000.times { data = [data] }

    assert_nothing_raised { extract({query: data}) }
  end

  test "payload extraction does not URL-decode past the configured maximum" do
    Aikido::Zen.config.extract_payloads_max_url_decoded_variants = 1

    payloads = extract({body: {"a" => "x%252520y"}})

    assert_includes payloads, Aikido::Zen::Payload.new("x%2520y", :body, "a")
    refute_includes payloads, Aikido::Zen::Payload.new("x%20y", :body, "a")
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

    payloads = extract({body: {"user" => {"session" => jwt}}})

    assert_includes payloads, Aikido::Zen::Payload.new("top", :body, "user.session<jwt>.sub")
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
end
