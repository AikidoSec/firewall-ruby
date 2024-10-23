# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::SinkTest < ActiveSupport::TestCase
  test "provides access to its name and scanners" do
    sink = Aikido::Zen::Sink.new("test", scanners: [NOOP])

    assert_equal "test", sink.name
    assert_equal [NOOP], sink.scanners
  end

  test "does not allow initializing without scanners" do
    assert_raises ArgumentError do
      Aikido::Zen::Sink.new("test", scanners: [])
    end
  end

  test "#scan passes the given params to each scanner, plus sink and context" do
    scan_params = nil
    scanner = ->(**data) {
      scan_params = data
      nil
    }

    sink = Aikido::Zen::Sink.new("test", scanners: [scanner])
    sink.scan(foo: 1, bar: 2)

    assert_equal({context: nil, foo: 1, bar: 2, sink: sink}, scan_params)
  end

  test "#scan passes the current context if present as :context" do
    scan_params = nil
    scanner = ->(**data) {
      scan_params = data
      nil
    }

    Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env({})

    sink = Aikido::Zen::Sink.new("test", scanners: [scanner])
    sink.scan(foo: 1, bar: 2)

    assert_equal Aikido::Zen.current_context, scan_params[:context]
  ensure
    Aikido::Zen.current_context = nil
  end

  test "#scan returns a Scan object" do
    sink = Aikido::Zen::Sink.new("test", scanners: [NOOP])

    scan = sink.scan(foo: 1, bar: 2)

    assert_kind_of Aikido::Zen::Scan, scan
    refute scan.attack?
  end

  # rubocop:disable Lint/RaiseException
  test "#scan returns nil if protection is disabled for the current context" do
    context = Minitest::Mock.new
    context.expect :protection_disabled?, true

    sink = Aikido::Zen::Sink.new("test", reporter: NOOP, scanners: [
      ->(**data) { raise Exception, "oops" } # StandardError would be caught
    ])

    assert_nothing_raised do
      scan = sink.scan(context: context)
      assert_nil scan
    end

    assert_mock context
  end
  # rubocop:enable Lint/RaiseException

  # rubocop:disable Lint/RaiseException
  test "#scan stops after the first Attack is detected" do
    attack = Aikido::Zen::Attack.new(context: nil, sink: nil, operation: nil)
    sink = Aikido::Zen::Sink.new("test", reporter: NOOP, scanners: [
      ->(**data) { attack },
      ->(**data) { raise Exception, "oops" } # StandardError would be caught
    ])

    assert_nothing_raised do
      scan = sink.scan(foo: 1, bar: 2)

      assert scan.attack?
      assert_equal attack, scan.attack
      assert_empty scan.errors
    end
  end
  # rubocop:enable Lint/RaiseException

  test "#scan reports the scan to the defined reporter" do
    reported_scans = []
    reporter = ->(scan) { reported_scans << scan }

    sink = Aikido::Zen::Sink.new("test", scanners: [NOOP], reporter: reporter)

    scan = sink.scan(foo: 1, bar: 2)

    assert_equal [scan], reported_scans
  end

  test "#scan captures errors raised by a scanner" do
    error = RuntimeError.new("oops")
    scanner = ->(**data) { raise error }
    sink = Aikido::Zen::Sink.new("test", scanners: [scanner])

    assert_nothing_raised do
      scan = sink.scan(foo: 1, bar: 2)

      assert_includes scan.errors, {error: error, scanner: scanner}
    end
  end

  test "#scan logs InternalsErrors besides capturing them" do
    error = Aikido::Zen::InternalsError.new("<query> for SQLi", "loading", "libzen.so")
    scanner = ->(**) { raise error }
    sink = Aikido::Zen::Sink.new("test", scanners: [scanner])

    assert_nothing_raised do
      scan = sink.scan(foo: 1, bar: 2)
      assert_includes scan.errors, {error: error, scanner: scanner}

      assert_logged :warn, error.message
    end
  end

  test "#scan tracks how long it takes to run the scanners" do
    scanner = ->(**data) { sleep 0.001 and nil }
    sink = Aikido::Zen::Sink.new("test", scanners: [scanner])

    scan = sink.scan(foo: 1, bar: 2)
    assert scan.duration > 0.001
  end

  class TestRegistry < ActiveSupport::TestCase
    Sinks = Aikido::Zen::Sinks

    test "Sinks.add defines a new sink and registers it" do
      assert_changes -> { Sinks.registry.keys }, from: [], to: ["test"] do
        sink = Sinks.add("test", scanners: [NOOP])

        assert_kind_of Aikido::Zen::Sink, sink
        assert_equal "test", sink.name
        assert_equal [NOOP], sink.scanners
      end
    end

    test "adding a sink to the registry marks the corresponding Package as supported" do
      package = Aikido::Zen::Package.new("test", Gem::Version.new("1.0.0"))
      refute package.supported?

      Sinks.add(package.name, scanners: [NOOP])
      assert package.supported?
    end

    test "registering a sink more than once raises an error" do
      Sinks.add("test", scanners: [NOOP])

      assert_raises ArgumentError do
        Sinks.add("test", scanners: [NOOP])
      end
    end
  end
end
