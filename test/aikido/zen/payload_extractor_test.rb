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

  test "payload extraction does not recurse past the configured maximum depth" do
    Aikido::Zen.config.extract_payloads_max_depth = 2

    data = {"a" => {"b" => "kept at the depth limit", "c" => {"d" => "dropped past the depth limit"}}}
    payloads = extract({body: data})

    assert_includes payloads, Aikido::Zen::Payload.new("kept at the depth limit", :body, "a.b")
    refute_includes payloads, Aikido::Zen::Payload.new("dropped past the depth limit", :body, "a.c.d")
  end

  test "payload extraction does not URL-decode past the configured maximum" do
    Aikido::Zen.config.extract_payloads_max_url_decoded_variants = 1

    payloads = extract({body: {"a" => "x%252520y"}})

    assert_includes payloads, Aikido::Zen::Payload.new("x%2520y", :body, "a")
    refute_includes payloads, Aikido::Zen::Payload.new("x%20y", :body, "a")
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
