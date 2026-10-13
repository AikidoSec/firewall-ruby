# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::HelpersTest < ActiveSupport::TestCase
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
end
