# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::HelpersTest < ActiveSupport::TestCase
  include JWTHelpers

  Helpers = Aikido::Zen::Helpers

  test ".encode_safely returns valid UTF-8 strings unchanged" do
    assert_equal "Mozilla é", Helpers.encode_safely("Mozilla é")
  end

  test ".encode_safely replaces invalid bytes in UTF-8 strings" do
    input = "a\xFFb"
    refute input.valid_encoding?

    result = Helpers.encode_safely(input)

    assert_equal "a�b", result
    assert result.valid_encoding?
  end

  test ".encode_safely replaces invalid bytes in binary strings" do
    result = Helpers.encode_safely("a\xFFb".b)

    assert_equal "a�b", result
    assert result.valid_encoding?
  end

  test ".encode_safely replaces a truncated multibyte sequence in a binary string once" do
    assert_equal "a�", Helpers.encode_safely("a\xE2\x82".b)
  end

  test ".encode_safely keeps valid UTF-8 in binary strings" do
    result = Helpers.encode_safely("Mozilla é".b)

    assert_equal "Mozilla é", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test ".encode_safely transcodes other encodings to UTF-8" do
    result = Helpers.encode_safely("Mozilla é".encode("ISO-8859-1"))

    assert_equal "Mozilla é", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test ".encode_safely does not modify the given string" do
    input = "Mozilla é".b.freeze

    Helpers.encode_safely(input)

    assert_equal Encoding::BINARY, input.encoding
    assert_equal "Mozilla é".b, input
  end

  test ".decode_jwt_payload returns the decoded payload part of a JWT" do
    jwt = encode_jwt({"sub" => "1234", "nested" => {"a" => "b"}})

    assert_equal({"sub" => "1234", "nested" => {"a" => "b"}}, Helpers.decode_jwt_payload(jwt))
  end

  test ".decode_jwt_payload returns non-ASCII claims as UTF-8 strings" do
    jwt = encode_jwt({"name" => "José"})

    name = Helpers.decode_jwt_payload(jwt)["name"]

    assert_equal "José", name
    assert_equal Encoding::UTF_8, name.encoding
  end

  test ".decode_jwt_payload returns the payload when it is a JSON array, not an object" do
    jwt = encode_jwt(["one", "two"])

    assert_equal ["one", "two"], Helpers.decode_jwt_payload(jwt)
  end

  test ".decode_jwt_payload returns the payload whether or not the payload part has base64 padding" do
    payload = {"sub" => "padded"}

    assert_equal payload, Helpers.decode_jwt_payload(encode_jwt(payload, padding: true))
    assert_equal payload, Helpers.decode_jwt_payload(encode_jwt(payload, padding: false))
  end

  test ".decode_jwt_payload returns the payload when the payload part contains line breaks" do
    payload = {"sub" => "x" * 100}
    wrapped = [JSON.generate(payload)].pack("m") # "m" wraps every 60 characters; "m0" does not.

    # Make sure the input really contains line breaks.
    assert_includes wrapped, "\n"

    assert_equal payload, Helpers.decode_jwt_payload(["header", wrapped, "signature"].join("."))
  end

  test ".decode_jwt_payload returns the payload from a payload part that uses the standard base64 alphabet" do
    payload = {"a" => "~~~???>>>"}
    standard = [JSON.generate(payload)].pack("m0")

    # Make sure the input really uses the characters that differ from base64url.
    assert_includes standard, "+"
    assert_includes standard, "/"

    assert_equal payload, Helpers.decode_jwt_payload(["header", standard, "signature"].join("."))
  end

  test ".decode_jwt_payload returns the payload from a payload part that is not strictly base64url" do
    payload = encode_jwt_part({"sub" => "x"})

    [
      "#{payload}===", # extra padding
      payload.dup.insert(4, "!!") # stray characters
    ].each do |lenient_payload|
      jwt = ["header", lenient_payload, "signature"].join(".")

      assert_equal({"sub" => "x"}, Helpers.decode_jwt_payload(jwt), "expected the payload from #{jwt.inspect}")
    end
  end

  test ".decode_jwt_payload ignores the header and signature, whatever they contain" do
    payload = encode_jwt_part({"sub" => "x"})

    other_parts = [
      "",
      "not base64!",
      "\xff\xfe", # not valid UTF-8
      "bm90IGpzb24", # valid base64url, but not JSON
      encode_jwt_part({"alg" => "none"}) # valid base64url JSON
    ]

    other_parts.product(other_parts).each do |first, last|
      jwt = [first, payload, last].join(".")

      assert_equal({"sub" => "x"}, Helpers.decode_jwt_payload(jwt), "expected the payload from #{jwt.inspect}")
    end
  end

  test ".decode_jwt_payload returns the payload of the smallest string worth decoding" do
    # An empty header and signature around the smallest JSON value with a string.
    jwt = ".#{encode_jwt_part("0")}."

    assert_equal Helpers::MIN_JWT_LENGTH, jwt.length
    assert_equal "0", Helpers.decode_jwt_payload(jwt)
  end

  test ".decode_jwt_payload returns nil for a string shorter than the smallest worth decoding" do
    jwt = ".#{encode_jwt_part(0)}."

    assert_operator jwt.length, :<, Helpers::MIN_JWT_LENGTH
    assert_nil Helpers.decode_jwt_payload(jwt)
  end

  test ".decode_jwt_payload returns nil for a string that is not three dot-separated parts around a base64 encoded JSON payload" do
    [
      "no dots in this string",
      "only.two parts in this string",
      "too.many.parts.in.this.string",
      "aaaa.bbbb.cccc", # three parts but not base64url JSON
      "head.\xfe\xfe\xfe\xfe\xfe\xfe.sig", # payload part is not valid UTF-8
      [encode_jwt_part({"alg" => "none"}), "bm90IGpzb24", "sig"].join(".")
    ].each do |value|
      assert_nil Helpers.decode_jwt_payload(value), "expected nil for #{value.inspect}"
    end
  end
end
