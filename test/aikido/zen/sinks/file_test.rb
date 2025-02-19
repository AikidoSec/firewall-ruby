# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::FileTest < ActiveSupport::TestCase
  # The following tests validates that the methods still behave as expected even though they are monkey patched
  class NormalExecutionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    test "File.read" do
      Helpers.temp_file "path-traversal-sink-read" do |tmp_file|
        tmp_file.write "some content"
        tmp_file.close
        assert_equal File.read(tmp_file.path), "some content"
      end
    end

    test "File.write" do
      path = Helpers.temp_file_name "path-traversal-sink-write"
      File.write path, "path-traversal-sink-write"

      assert_equal File.read(path), "path-traversal-sink-write"
      File.unlink path
    end

    test "File.join" do
      assert_equal File.join("base"), "base"
      assert_equal File.join("base", "some"), "base/some"
      assert_equal File.join("base", "some", "path"), "base/some/path"
    end

    test "File.chmod" do
      Helpers.temp_file "path-traversal-sink-chmod" do |tmp_file|
        assert_equal File.chmod(0o755, tmp_file.path), 1
      end
    end
  end

  # The following tests are have a null `Context`, that means although they _might be_ attacks, they won't be
  # considered as such by the scanner
  class LookLikeAttackTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    test "File.read" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.read("../looks-like-an-attack")
        end
      end
    end

    test "File.write" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.write Helpers.temp_file_name + "/../looks-like-an-attack", "content"
        end
      end
    end

    test "File.join" do
      refute_attack do
        assert_equal File.join("base", "some", "/../", "looks-like-an-attack"), "base/some/../looks-like-an-attack"
      end
    end

    test "File.chmod" do
      refute_attack do
        assert_raise Errno::ENOENT do
          assert_equal 0, File.chmod(0o755, Helpers.temp_file_name)
        end
      end
    end
  end

  class AttackDetectionTest < ActiveSupport::TestCase
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

    test "attacks are detected by the scanner" do
      assert_path_traversal_attack "File.read" do
        File.read OFFENDER_PATH
      end

      assert_path_traversal_attack "File.write" do
        File.write OFFENDER_PATH, "content"
      end

      assert_path_traversal_attack "File.join" do
        File.join "some", "path", OFFENDER_PATH
      end

      assert_path_traversal_attack "File.chmod" do
        File.chmod 0o755, OFFENDER_PATH
      end
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
