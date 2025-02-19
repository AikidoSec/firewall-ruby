# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::FileTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  test "scanning does not interfere with `File.read` normally" do
    tmp_file = Tempfile.new("path-traversal-sink-read")

    begin
      tmp_file.write "some content"
      tmp_file.close

      assert_equal File.read(tmp_file.path), "some content"
    ensure
      tmp_file.unlink
    end
  end

  test "scanning does not interfere with `File.write` normally" do
    ::Dir::Tmpname.create("path-traversal-sink-write", Dir.tmpdir) do |path|
      File.write path, "path-traversal-sink-write"

      assert_equal File.read(path), "path-traversal-sink-write"
      File.unlink path
    end
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
      ::Dir::Tmpname.create("path-traversal-sink-write", Dir.tmpdir) do |path|
        assert_raise Errno::ENOENT do
          File.write path + "/../looks-like-an-attack", "content"
        end
      end
    end
  end

  test "scanning detects Path Traversal Attacks" do
    set_context_from_request_to "/?filename=../this-is-an-attack"

    error = assert_attack Aikido::Zen::Attacks::PathTraversalAttack do
      File.read("../this-is-an-attack")
    end

    assert_equal \
      error.message,
      "Path Traversal: Malicious user input «../this-is-an-attack» detected while calling method File.read"
  end
end
