# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::IOTest < ActiveSupport::TestCase
  class NormalExecutionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    test "IO.read" do
      Helpers.temp_file do |tmp_file|
        tmp_file.write "some content"
        tmp_file.close
        assert_equal "some content", IO.read(tmp_file.path)
      end
    end

    test "IO.write" do
      path = Helpers.temp_file_name "io-sink-write"
      IO.write path, "io-sink-write"
      assert_equal "io-sink-write", IO.read(path)
      File.unlink path
    end

    test "IO.foreach" do
      Helpers.temp_file do |tmp_file|
        tmp_file.write "line1\nline2\n"
        tmp_file.close
        lines = []
        IO.foreach(tmp_file.path) { |l| lines << l }
        assert_equal ["line1\n", "line2\n"], lines
      end
    end

    test "IO.readlines" do
      Helpers.temp_file do |tmp_file|
        tmp_file.write "line1\nline2\n"
        tmp_file.close
        assert_equal ["line1\n", "line2\n"], IO.readlines(tmp_file.path)
      end
    end

    test "IO.binread" do
      Helpers.temp_file do |tmp_file|
        tmp_file.write "binary"
        tmp_file.close
        assert_equal "binary", IO.binread(tmp_file.path)
      end
    end

    test "IO.binwrite" do
      path = Helpers.temp_file_name "io-sink-binwrite"
      IO.binwrite path, "binary"
      assert_equal "binary", IO.binread(path)
      File.unlink path
    end
  end

  class LookLikeAttackTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    LOOKS_LIKE_AN_ATTACK_PATH = "../looks-like-an-attack"

    test "IO.read" do
      refute_attack do
        assert_raise Errno::ENOENT do
          IO.read(LOOKS_LIKE_AN_ATTACK_PATH)
        end
      end
    end

    test "IO.write" do
      refute_attack do
        assert_raise Errno::ENOENT do
          IO.write Helpers.temp_file_name + "/" + LOOKS_LIKE_AN_ATTACK_PATH, "content"
        end
      end
    end

    test "IO.foreach" do
      refute_attack do
        assert_raise Errno::ENOENT do
          IO.foreach(LOOKS_LIKE_AN_ATTACK_PATH) { }
        end
      end
    end

    test "IO.readlines" do
      refute_attack do
        assert_raise Errno::ENOENT do
          IO.readlines(LOOKS_LIKE_AN_ATTACK_PATH)
        end
      end
    end

    test "IO.binread" do
      refute_attack do
        assert_raise Errno::ENOENT do
          IO.binread(LOOKS_LIKE_AN_ATTACK_PATH)
        end
      end
    end

    test "IO.binwrite" do
      refute_attack do
        assert_raise Errno::ENOENT do
          IO.binwrite Helpers.temp_file_name + "/" + LOOKS_LIKE_AN_ATTACK_PATH, "content"
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

      assert_equal operation, error.attack.operation
    end

    test "attacks are detected by the scanner" do
      assert_path_traversal_attack "IO.read" do
        IO.read OFFENDER_PATH
      end

      assert_path_traversal_attack "IO.write" do
        IO.write OFFENDER_PATH, "content"
      end

      assert_path_traversal_attack "IO.foreach" do
        IO.foreach(OFFENDER_PATH) { }
      end

      assert_path_traversal_attack "IO.readlines" do
        IO.readlines OFFENDER_PATH
      end

      assert_path_traversal_attack "IO.binread" do
        IO.binread OFFENDER_PATH
      end

      assert_path_traversal_attack "IO.binwrite" do
        IO.binwrite OFFENDER_PATH, "content"
      end
    end
  end

  module Helpers
    def self.temp_file_name(basename = "io-sink-temp-file")
      ::Dir::Tmpname.create(basename, Dir.tmpdir) { |path| return path }
    end

    def self.temp_file(filename = "io-sink-temp-file", &block)
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
