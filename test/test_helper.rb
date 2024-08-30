# frozen_string_literal: true

require "bundler"
Bundler.setup

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "aikido/firewall"
require "minitest/autorun"
require "active_support"
require "active_support/test_case"
require "active_support/testing/setup_and_teardown"
require "minitest/stub_const"
require "webmock/minitest"
require "action_dispatch"
require "action_dispatch/routing/inspector"
require "pathname"
require "debug" if RUBY_VERSION >= "3"

require_relative "support/fake_rails_app"
require_relative "support/puma"

class ActiveSupport::TestCase
  self.file_fixture_path = "test/fixtures"

  # Utility proc that does nothing.
  NOOP = ->(*args, **opts) {}

  # Reset any global state before each test
  setup do
    Aikido::Agent.instance_variable_set(:@info, nil)
    Aikido::Agent.instance_variable_set(:@config, nil)
    Aikido::Agent.instance_variable_set(:@runner, nil)
    Aikido::Firewall.instance_variable_set(:@settings, nil)

    @_old_sinks_registry = Aikido::Firewall::Sinks.registry.dup
    Aikido::Firewall::Sinks.registry.clear

    WebMock.reset!
  end

  teardown do
    # In case any test starts the agent background thread as a side effect, this
    # should make sure we're cleaning things up.
    Aikido::Agent.stop!

    Aikido::Firewall::Sinks.registry.replace(@_old_sinks_registry)
  end

  # Reset the routes in the test app defined in test/support/fake_rails_app to
  # avoid any leaks between tests.
  setup do
    new_routes = ActionDispatch::Routing::RouteSet.new
    Rails.application.instance_variable_set(:@routes, new_routes)
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

  module StubsCurrentContext
    # Override in tests to return the desired stub.
    def current_context
      @current_context ||= Aikido::Agent::Context.from_rack_env({})
    end

    def self.included(base)
      base.setup { Aikido::Agent.current_context = current_context }
      base.teardown { Aikido::Agent.current_context = nil }
    end
  end
end
