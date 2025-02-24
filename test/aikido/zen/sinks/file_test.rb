# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::FileTest < ActiveSupport::TestCase
  # The following tests validates that the methods still behave as expected even though they are monkey patched
  class NormalExecutionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    test "File.new" do
      Helpers.temp_file_name do |tmp_file|
        assert_nothing_raised do
          tmp_file.new(tmp_file)
          tmp_file.close
        end
      end
    end

    test "File.open" do
      Helpers.temp_file_name do |tmp_file|
        assert_nothing_raised do
          tmp_file.open(tmp_file)
          tmp_file.close
        end
      end
    end

    test "File.read" do
      Helpers.temp_file do |tmp_file|
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
      # It's possible to call this method with 0 arguments if you expand an array
      empty_array = []
      assert_equal File.join(*empty_array), ""
    end

    test "File.chmod" do
      Helpers.temp_file do |tmp_file|
        assert_equal File.chmod(0o755, tmp_file.path), 1
      end
    end

    # `File.chown` needs root permissions to be executed, so we trust on the LookLikeAttackTest::File.chown test

    test "File.rename" do
      Helpers.temp_file "from-path" do |tmp_file|
        to_path = Helpers.temp_file_name("to-path")
        File.rename tmp_file.path, to_path
        assert_path_exists to_path
      end
    end

    test "File.symlink" do
      Helpers.temp_file "from-path" do |tmp_file|
        to_path = Helpers.temp_file_name("to-path")
        File.symlink tmp_file.path, to_path
        assert_path_exists to_path
      end
    end

    test "File.truncate" do
      Helpers.temp_file do |tmp_file|
        tmp_file.write "some content"
        tmp_file.close
        assert_equal File.truncate(tmp_file.path, 100), 0
      end
    end

    test "File.unlink" do
      Helpers.temp_file do |tmp_file|
        assert_path_exists tmp_file.path
        File.unlink tmp_file.path
        refute File.exist?(tmp_file.path)
      end
    end

    test "File.delete" do
      Helpers.temp_file do |tmp_file|
        assert_path_exists tmp_file.path
        File.delete tmp_file.path
        refute File.exist?(tmp_file.path)
      end
    end

    test "File.utime" do
      Helpers.temp_file do |tmp_file|
        assert_equal 1, File.utime(Time.new(2000), Time.new(2000), tmp_file.path)
        assert_equal Time.new(2000), File.mtime(tmp_file.path)
        assert_equal Time.new(2000), File.atime(tmp_file.path)
      end
    end

    test "File.expand_path" do
      assert_equal "/some-path", File.expand_path("../some-path/this-wont-appear/..", "/")
    end
  end

  # The following tests are have a null `Context`, that means although they _might be_ attacks, they won't be
  # considered as such by the scanner
  class LookLikeAttackTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    LOOKS_LIKE_AN_ATTACK_PATH = "../looks-like-an-attack"

    test "File.new" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.new(LOOKS_LIKE_AN_ATTACK_PATH)
        end
      end
    end

    test "File.open" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.open(LOOKS_LIKE_AN_ATTACK_PATH)
        end
      end
    end

    test "File.read" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.read(LOOKS_LIKE_AN_ATTACK_PATH)
        end
      end
    end

    test "File.write" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.write Helpers.temp_file_name + "/" + LOOKS_LIKE_AN_ATTACK_PATH, "content"
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

    test "File.chown" do
      refute_attack do
        assert_raise Errno::EPERM do
          Helpers.temp_file do |tmp_file|
            assert_equal 0, File.chown(1, 1, tmp_file.path)
          end
        end
      end
    end

    test "File.rename" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.rename "some-path", LOOKS_LIKE_AN_ATTACK_PATH
        end
      end
    end

    test "File.symlink" do
      refute_attack do
        assert_raises(Errno::EROFS, Errno::EACCES) do
          File.symlink "some-fake-path", "/" + LOOKS_LIKE_AN_ATTACK_PATH
        end
      end
    end

    test "File.truncate" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.truncate LOOKS_LIKE_AN_ATTACK_PATH, 1
        end
      end
    end

    test "File.unlink" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.unlink "some-fake-path"
        end
      end
    end

    test "File.delete" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.delete "some-fake-path"
        end
      end
    end

    test "File.utime" do
      refute_attack do
        assert_raise Errno::ENOENT do
          File.utime Time.new, Time.new, "some-fake-path"
        end
      end
    end

    test "File.expand_path" do
      refute_attack do
        file_expand_path = File.expand_path(LOOKS_LIKE_AN_ATTACK_PATH, __FILE__)
        refute file_expand_path.include?("..")
        assert file_expand_path.end_with?("looks-like-an-attack")
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
      assert_path_traversal_attack "File.new" do
        File.new OFFENDER_PATH
      end

      assert_path_traversal_attack "File.open" do
        File.open OFFENDER_PATH
      end

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

      assert_path_traversal_attack "File.chown" do
        File.chown 1, 1, OFFENDER_PATH
      end

      assert_path_traversal_attack "File.rename" do
        File.rename OFFENDER_PATH, "some-path"
      end

      assert_path_traversal_attack "File.rename" do
        File.rename "some-path", OFFENDER_PATH
      end

      assert_path_traversal_attack "File.rename" do
        File.rename OFFENDER_PATH, OFFENDER_PATH
      end

      assert_path_traversal_attack "File.symlink" do
        File.symlink OFFENDER_PATH, "some-path"
      end

      assert_path_traversal_attack "File.symlink" do
        File.symlink "some-path", OFFENDER_PATH
      end

      assert_path_traversal_attack "File.symlink" do
        File.symlink OFFENDER_PATH, OFFENDER_PATH
      end

      assert_path_traversal_attack "File.truncate" do
        File.truncate OFFENDER_PATH, 1
      end

      assert_path_traversal_attack "File.unlink" do
        File.unlink "path-ok", OFFENDER_PATH, "another-path"
      end

      assert_path_traversal_attack "File.delete" do
        File.delete "path-ok", OFFENDER_PATH, "another-path"
      end

      assert_path_traversal_attack "File.utime" do
        File.utime Time.new, Time.new, "path-ok", OFFENDER_PATH, "another-path"
      end

      assert_path_traversal_attack "File.expand_path" do
        File.expand_path OFFENDER_PATH
      end
    end
  end

  module Helpers
    def self.temp_file_name(basename = "path-traversal-sink-temp-file")
      ::Dir::Tmpname.create(basename, Dir.tmpdir) do |path|
        return path
      end
    end

    def self.temp_file(filename = "path-traversal-sink-temp-file", &block)
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
