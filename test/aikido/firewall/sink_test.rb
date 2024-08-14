# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::SinkTest < ActiveSupport::TestCase
  NOOP = ->(*args, **opts) {}

  test "provides access to its name and scanners" do
    sink = Aikido::Firewall::Sink.new("test", scanners: [NOOP])

    assert_equal "test", sink.name
    assert_equal [NOOP], sink.scanners
  end

  test "does not allow initializing without scanners" do
    assert_raises ArgumentError do
      Aikido::Firewall::Sink.new("test", scanners: [])
    end
  end

  test "#scan passes the given params to each scanner, plus sink and request" do
    scan_params = nil
    scanner = ->(**data) {
      scan_params = data
      nil
    }

    sink = Aikido::Firewall::Sink.new("test", scanners: [scanner])
    sink.scan(foo: 1, bar: 2)

    assert_equal({request: nil, foo: 1, bar: 2, sink: sink}, scan_params)
  end

  test "#scan passes the current request if present as :request" do
    scan_params = nil
    scanner = ->(**data) {
      scan_params = data
      nil
    }

    Aikido::Agent.current_request = Aikido::Agent::Request.new({})

    sink = Aikido::Firewall::Sink.new("test", scanners: [scanner])
    sink.scan(foo: 1, bar: 2)

    assert_equal Aikido::Agent.current_request, scan_params[:request]
  ensure
    Aikido::Agent.current_request = nil
  end

  test "#scan returns a Scan object" do
    sink = Aikido::Firewall::Sink.new("test", scanners: [NOOP])

    scan = sink.scan(foo: 1, bar: 2)

    assert_kind_of Aikido::Firewall::Scan, scan
    refute scan.attack?
  end

  # rubocop:disable Link/RaiseException
  test "#scan stops after the first Attack is detected" do
    attack = Aikido::Firewall::Attack.new(request: nil, sink: nil)
    sink = Aikido::Firewall::Sink.new("test", reporter: NOOP, scanners: [
      ->(**data) { attack },
      ->(**data) { raise Exception, "oops" } # Exception would not be caught
    ])

    assert_nothing_raised do
      scan = sink.scan(foo: 1, bar: 2)

      assert scan.attack?
      assert_empty scan.errors
    end
  end
  # rubocop:enable Link/RaiseException

  test "#scan reports the scan to the defined reporter" do
    reported_scans = []
    reporter = ->(scan) { reported_scans << scan }

    sink = Aikido::Firewall::Sink.new("test", scanners: [NOOP], reporter: reporter)

    scan = sink.scan(foo: 1, bar: 2)

    assert_equal [scan], reported_scans
  end

  test "#scan captures errors raised by a scanner" do
    error = RuntimeError.new("oops")
    scanner = ->(**data) { raise error }
    sink = Aikido::Firewall::Sink.new("test", scanners: [scanner])

    assert_nothing_raised do
      scan = sink.scan(foo: 1, bar: 2)

      assert_includes scan.errors, {error: error, scanner: scanner}
    end
  end

  test "#scan tracks how long it takes to run the scanners" do
    scanner = ->(**data) { sleep 0.001 and nil }
    sink = Aikido::Firewall::Sink.new("test", scanners: [scanner])

    scan = sink.scan(foo: 1, bar: 2)
    assert scan.duration > 0.001
  end
end
