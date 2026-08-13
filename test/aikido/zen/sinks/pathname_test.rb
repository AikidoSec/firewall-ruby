# frozen_string_literal: true

require "test_helper"
require "pathname"

class Aikido::Zen::Sinks::PathnameTest < ActiveSupport::TestCase
  class NormalExecutionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    test "Pathname#cleanpath with a normal relative path" do
      refute_attack do
        result = Pathname.new("some/./path/../file.txt").cleanpath
        assert_equal Pathname.new("some/file.txt"), result
      end
    end

    test "Pathname#cleanpath with an absolute path" do
      refute_attack do
        result = Pathname.new("/var/app/data/file.txt").cleanpath
        assert_equal Pathname.new("/var/app/data/file.txt"), result
      end
    end
  end

  class LookLikeAttackTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    test "Pathname#cleanpath with a traversal path but no context" do
      refute_attack do
        result = Pathname.new("../../../../etc/passwd").cleanpath
        assert_equal Pathname.new("../../../../etc/passwd"), result
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

    test "Pathname#cleanpath detects traversal before it is resolved" do
      assert_path_traversal_attack "Pathname.cleanpath" do
        Pathname.new(OFFENDER_PATH).cleanpath
      end
    end

    test "detects traversal in paths joined with a base before cleanpath" do
      set_context_from_request_to "/?filename=#{OFFENDER_PATH}"

      assert_attack Aikido::Zen::Attacks::PathTraversalAttack do
        Pathname.new(File.join("/var/app/uploads", OFFENDER_PATH)).cleanpath
      end
    end

    test "detects the Pathname.cleanpath bypass used to reach sensitive files" do
      raw_input = "../../../../etc/passwd"
      set_context_from_request_to "/?filename=#{raw_input}"

      assert_attack Aikido::Zen::Attacks::PathTraversalAttack do
        Pathname.new(File.join("/var/app/uploads", raw_input)).cleanpath
      end
    end
  end
end
