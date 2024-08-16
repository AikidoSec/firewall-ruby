# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "aikido/firewall"
require "minitest/autorun"
require "active_support/test_case"
require "minitest/stub_const"
require "webmock/minitest"
require "active_support/testing/setup_and_teardown"
require "pathname"
require "debug"

class ActiveSupport::TestCase
  self.file_fixture_path = "test/fixtures"

  # Utility proc that does nothing.
  NOOP = ->(*args, **opts) {}

  # Reset any global state before each test
  setup do
    Aikido::Agent.instance_variable_set(:@info, nil)
    Aikido::Agent.instance_variable_set(:@config, nil)
    Aikido::Firewall.instance_variable_set(:@settings, nil)

    WebMock.reset!
  end

  # Capture log output and make it testable
  setup do
    @log_output = StringIO.new
    Aikido::Agent.config.logger.reopen(@log_output)
  end

  # rubocop:disable Style/OptionalArguments
  def assert_logged(level = nil, pattern)
    @log_output.rewind

    lines = @log_output.readlines.map(&:chomp)
    match_level = level.to_s.upcase if level

    reason = "no #{level.inspect if level} log message" +
      "matches #{pattern.inspect}".squeeze("\s") +
      "Log messages:\n#{lines.map { |line| "\t* #{line}" }.join("\n")}"

    assert lines.any? { |line| pattern === line && (match_level === line or true) }, reason
  end

  def refute_logged(level = nil, pattern)
    @log_output.rewind

    lines = @log_output.readlines.map(&:chomp)
    match_level = level.to_s.upcase if level

    reason = "expected no #{level.inspect if level} log messages " +
      "to match #{pattern.inspect}".squeeze("\s") +
      "Log messages:\n#{lines.map { |line| "\t* #{line}" }.join("\n")}"

    refute lines.any? { |line| pattern === line && (match_level === line or true) }, reason
  end
  # rubocop:enable Style/OptionalArguments

  module StubsCurrentRequest
    # Override in tests to return the desired stub.
    def current_request
      @current_request ||= Aikido::Agent::Request.new({})
    end

    def self.included(base)
      base.setup { Aikido::Agent.current_request = current_request }
      base.teardown { Aikido::Agent.current_request = nil }
    end
  end
end
