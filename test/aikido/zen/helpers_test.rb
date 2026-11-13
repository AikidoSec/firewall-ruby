# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::HelpersTest < ActiveSupport::TestCase
  include JWTHelpers

  Helpers = Aikido::Zen::Helpers

  test ".encode_safely keeps valid UTF-8 strings" do
    assert_equal "Mozilla é", Helpers.encode_safely("Mozilla é")
  end

  test ".encode_safely does not modify valid UTF-8 strings" do
    input = +"Mozilla é"

    Helpers.encode_safely(input)

    assert_equal Encoding::UTF_8, input.encoding
    assert_equal "Mozilla é", input
  end

  test ".encode_safely does not copy valid UTF-8 strings" do
    input = +"Mozilla é"

    assert_same input, Helpers.encode_safely(input)
  end

  test ".encode_safely accepts frozen valid UTF-8 strings" do
    input = "Mozilla é"
    assert_predicate input, :frozen?

    result = Helpers.encode_safely(input)

    assert_equal "Mozilla é", result
  end

  test ".encode_safely replaces invalid bytes in UTF-8 strings" do
    input = "a\xFFb"
    refute input.valid_encoding?

    result = Helpers.encode_safely(input)

    assert_equal "a�b", result
    assert result.valid_encoding?
  end

  test ".encode_safely does not modify invalid UTF-8 strings" do
    input = +"a\xFFb"

    Helpers.encode_safely(input)

    assert_equal Encoding::UTF_8, input.encoding
    assert_equal "a\xFFb".b, input.b
  end

  test ".encode_safely copies invalid UTF-8 strings" do
    input = +"a\xFFb"

    refute_same input, Helpers.encode_safely(input)
  end

  test ".encode_safely accepts frozen invalid UTF-8 strings" do
    input = "a\xFFb"
    assert_predicate input, :frozen?

    result = Helpers.encode_safely(input)

    assert_equal "a�b", result
    assert result.valid_encoding?
  end

  test ".encode_safely keeps valid UTF-8 in binary strings" do
    result = Helpers.encode_safely("Mozilla é".b)

    assert_equal "Mozilla é", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test ".encode_safely replaces invalid bytes in binary strings" do
    result = Helpers.encode_safely("a\xFFb".b)

    assert_equal "a�b", result
    assert result.valid_encoding?
  end

  test ".encode_safely replaces a truncated multibyte sequence in binary strings with a single replacement character" do
    assert_equal "a�", Helpers.encode_safely("a\xE2\x82".b)
  end

  test ".encode_safely does not modify binary strings" do
    input = +"a\xFFb".b

    Helpers.encode_safely(input)

    assert_equal Encoding::BINARY, input.encoding
    assert_equal "a\xFFb".b, input
  end

  test ".encode_safely copies binary strings" do
    valid = +"Mozilla é".b
    invalid = +"a\xFFb".b

    refute_same valid, Helpers.encode_safely(valid)
    refute_same invalid, Helpers.encode_safely(invalid)
  end

  test ".encode_safely accepts frozen binary strings" do
    result = Helpers.encode_safely("Mozilla é".b.freeze)

    assert_equal "Mozilla é", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test ".encode_safely transcodes other encodings to UTF-8" do
    result = Helpers.encode_safely("Mozilla é".encode("ISO-8859-1"))

    assert_equal "Mozilla é", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test ".encode_safely replaces invalid bytes in other encodings" do
    result = Helpers.encode_safely((+"a\xFFb").force_encoding(Encoding::Shift_JIS))

    assert_equal "a�b", result
    assert result.valid_encoding?
  end

  test ".encode_safely replaces undefined characters in other encodings" do
    result = Helpers.encode_safely((+"a\x81b").force_encoding(Encoding::Windows_1252))

    assert_equal "a�b", result
    assert result.valid_encoding?
  end

  test ".encode_safely does not modify strings in other encodings" do
    input = "Mozilla é".encode("ISO-8859-1")

    Helpers.encode_safely(input)

    assert_equal Encoding::ISO_8859_1, input.encoding
    assert_equal "Mozilla \xE9".b, input.b
  end

  test ".encode_safely copies strings in other encodings" do
    input = "Mozilla é".encode("ISO-8859-1")

    refute_same input, Helpers.encode_safely(input)
  end

  test ".encode_safely accepts frozen strings in other encodings" do
    result = Helpers.encode_safely("Mozilla é".encode("ISO-8859-1").freeze)

    assert_equal "Mozilla é", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test ".encode_safely transcodes ASCII-only strings in other encodings that are ASCII-compatible to UTF-8" do
    [Encoding::US_ASCII, Encoding::ISO_8859_1, Encoding::Windows_1252, Encoding::Shift_JIS].each do |encoding|
      result = Helpers.encode_safely("Mozilla/5.0 ~\\".encode(encoding))

      assert_equal "Mozilla/5.0 ~\\", result, encoding.name
      assert_equal Encoding::UTF_8, result.encoding, encoding.name
    end
  end

  test ".encode_safely transcodes ASCII-only strings in other encodings that are not ASCII-compatible to UTF-8" do
    [Encoding::UTF_16LE, Encoding::UTF_16BE, Encoding::UTF_32LE, Encoding::UTF_32BE].each do |encoding|
      result = Helpers.encode_safely("Mozilla".encode(encoding))

      assert_equal "Mozilla", result, encoding.name
      assert_equal Encoding::UTF_8, result.encoding, encoding.name
    end
  end

  test ".encode_safely does not modify ASCII-only strings in other encodings" do
    input = "Mozilla".encode("US-ASCII")

    Helpers.encode_safely(input)

    assert_equal Encoding::US_ASCII, input.encoding
    assert_equal "Mozilla".b, input.b
  end

  test ".encode_safely copies ASCII-only strings in other encodings" do
    input = "Mozilla".encode("US-ASCII")

    refute_same input, Helpers.encode_safely(input)
  end

  test ".encode_safely accepts frozen ASCII-only strings in other encodings" do
    result = Helpers.encode_safely("Mozilla".encode("US-ASCII").freeze)

    assert_equal "Mozilla", result
    assert_equal Encoding::UTF_8, result.encoding
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
