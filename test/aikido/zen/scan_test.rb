# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::ScanTest < ActiveSupport::TestCase
  setup do
    @sink = Object.new
    @context = Object.new

    @scan = Aikido::Zen::Scan.new(sink: @sink, context: @context)
  end

  test "knows if it has been performed yet" do
    refute @scan.performed?

    @scan.perform { nil }

    assert @scan.performed?
  end

  test "it is not considered an attack if the block returns nil" do
    @scan.perform { nil }

    refute @scan.attack?
    assert_nil @scan.attack
  end

  test "it is considered an attack if the block returns an Attack" do
    attack = Aikido::Zen::Attack.new(context: @context, sink: @sink, operation: "test")

    @scan.perform { attack }

    assert @scan.attack?
    assert_equal attack, @scan.attack
  end

  test "#perform measures the duration of the block using the system's monotonic clock" do
    times = [1, 4]
    Process.stub :clock_gettime, ->(_) { times.shift } do
      @scan.perform { nil }

      assert_equal 3, @scan.duration
    end
  end

  test "#track_error collects the scanner object and the error for future analysis" do
    scanner = ->(**data) {}
    error = RuntimeError.new("oops")

    @scan.track_error(error, scanner)

    assert_includes @scan.errors, {error: error, scanner: scanner}
  end
end
