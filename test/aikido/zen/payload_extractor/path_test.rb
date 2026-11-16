# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::PayloadExtractor::PathTest < ActiveSupport::TestCase
  JWT_MARKER = Aikido::Zen::PayloadExtractor::Path::JWT_MARKER
  FILE_JOIN_MARKER = Aikido::Zen::PayloadExtractor::Path::FILE_JOIN_MARKER

  def path_for(*segments)
    Aikido::Zen::PayloadExtractor::Path.new.tap do |path|
      segments.each { |segment| path.push(segment) }
    end
  end

  test "#to_s joins keys and indexes with dots" do
    assert_equal "a.0.b", path_for("a", 0, "b").to_s
  end

  test "#to_s has no separator before the first segment" do
    assert_equal "", path_for.to_s
    assert_equal "a", path_for("a").to_s
  end

  test "#to_s keeps an empty key as an empty segment" do
    assert_equal ".k", path_for("", "k").to_s
    assert_equal "a..b", path_for("a", "", "b").to_s
  end

  test "#to_s encodes keys as valid UTF-8" do
    string = path_for("café", "k\xC3\xA9".b, "bad\xFF".b).to_s

    assert_equal "café.ké.bad�", string
    assert_equal Encoding::UTF_8, string.encoding
    assert string.valid_encoding?
  end

  test "#to_s formats a jwt path marker after a key" do
    assert_equal "token<jwt>.sub", path_for("token", JWT_MARKER, "sub").to_s
  end

  test "#to_s formats a File.join path marker after a key" do
    assert_equal "path<File.join>", path_for("path", FILE_JOIN_MARKER).to_s
  end

  test "#to_s formats a path marker at the start of the path" do
    assert_equal "<jwt>", path_for(JWT_MARKER).to_s
  end

  test "#to_s formats path markers in a row without separators" do
    assert_equal "token<jwt><File.join>", path_for("token", JWT_MARKER, FILE_JOIN_MARKER).to_s
  end

  test "#to_s is not affected by later changes to the path" do
    path = path_for("a", "b")
    string = path.to_s

    path.pop
    path.push("c")

    assert_equal "a.b", string
    assert_equal "a.c", path.to_s
  end

  test "#pop removes the last segment" do
    path = path_for("a", "b")

    path.pop

    assert_equal "a", path.to_s
  end

  test "#size is the number of segments" do
    assert_equal 0, path_for.size
    assert_equal 3, path_for("a", 0, "b").size
    assert_equal 2, path_for("a", JWT_MARKER).size
  end
end
