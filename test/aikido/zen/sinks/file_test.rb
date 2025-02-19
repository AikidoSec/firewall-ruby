# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::FileTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  test "scanning does not interfere with `File.read` normally" do
    Helpers.temp_file "path-traversal-sink-read" do |tmp_file|
      tmp_file.write "some content"
      tmp_file.close
      assert_equal File.read(tmp_file.path), "some content"
    end
  end

  test "scanning does not interfere with `File.write` normally" do
    path = Helpers.temp_file_name "path-traversal-sink-write"
    File.write path, "path-traversal-sink-write"

    assert_equal File.read(path), "path-traversal-sink-write"
    File.unlink path
  end

  test "scanning does not interfere with `File.join` normally" do
    assert_equal File.join("base"), "base"
    assert_equal File.join("base", "some"), "base/some"
    assert_equal File.join("base", "some", "path"), "base/some/path"
  end

  test "does not fail when the context is null but looks like an attack" do
    # We expect the next `File.(read|write)`  will fail *because* the file does not exist,
    # but *not because* it is Path Traversal Attack
    refute_attack do
      assert_raise Errno::ENOENT do
        File.read("../looks-like-an-attack")
      end
    end

    refute_attack do
      path = Helpers.temp_file_name
      assert_raise Errno::ENOENT do
        File.write path + "/../looks-like-an-attack", "content"
      end
    end

    # Check for `File.join`
    refute_attack do
      assert_equal File.join("base", "some", "/../", "looks-like-an-attack"), "base/some/../looks-like-an-attack"
    end
  end

  class AttacksDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    OFFENDER_PATH = "../this-is-an-attack"

    def assert_path_traversal_attack(operation, &block)
      set_context_from_request_to "/?filename=#{OFFENDER_PATH}"

      error = assert_attack Aikido::Zen::Attacks::PathTraversalAttack, &block

      assert_equal \
        error.message,
        "Path Traversal: Malicious user input «#{OFFENDER_PATH}» detected while calling method #{operation}"
    end

    test "File.read" do
      assert_path_traversal_attack "File.read" do
        File.read OFFENDER_PATH
      end
    end

    test "File.write" do
      assert_path_traversal_attack "File.write" do
        File.write OFFENDER_PATH, "content"
      end
    end

    test "File.join" do
      assert_path_traversal_attack "File.join" do
        File.join "some", "path", OFFENDER_PATH
      end
    end

  module Helpers
    def self.temp_file_name(basename = "path-traversal-sink-write")
      ::Dir::Tmpname.create(basename, Dir.tmpdir) do |path|
        return path
      end
    end

    def self.temp_file(filename, &block)
      tmp_file = Tempfile.new filename

      begin
        yield tmp_file
        tmp_file.close
      ensure
        tmp_file.unlink
      end
    end
  end
end
