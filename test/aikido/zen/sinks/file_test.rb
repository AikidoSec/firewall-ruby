# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::FileTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include SinkAttackHelpers

  test "scanning does not interfere with File.read normally" do
    tmp_file = Tempfile.new("path-traversal-sink-read")

    begin
      tmp_file.write "some content"
      tmp_file.close

      assert_equal File.read(tmp_file.path), "some content"
    ensure
      tmp_file.unlink
    end
  end

  test "scanning does not interfere with File.write normally" do
    ::Dir::Tmpname.create("path-traversal-sink-write", Dir.tmpdir) do |path|
      File.write path, "path-traversal-sink-write"

      assert_equal File.read(path), "path-traversal-sink-write"
      File.unlink path
    end
  end

  test "does not fail when the context is null" do
    refute_attack do
      # We expect the next `File.read` will fail *because& the file does not exist,
      # but no because it is Path Traversal Attack
      assert_raise Errno::ENOENT do
        File.read("../this-is-an-attack")
      end
    end
  end
end
