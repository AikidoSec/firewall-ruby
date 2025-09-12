# frozen_string_literal: true

require "bundler"
Bundler.setup

require "simplecov-lcov" if RUBY_VERSION >= "3"
require "simplecov"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "aikido/zen"
require "minitest/autorun"
require "minitest/stub_const"
require "active_support"
require "active_support/test_case"
require "active_support/testing/setup_and_teardown"
require "action_dispatch"
require "action_dispatch/routing/inspector"
require "pathname"
require "debug" if RUBY_VERSION >= "3"
require "support/capture_stream"

class FakeDetachedAgent
  extend Forwardable

  def_delegators :@collector, :track_request, :track_route, :track_outbound, :track_scan, :track_user, :track_attack
  def_delegator :@rate_limiter, :calculate_rate_limits

  def initialize(collector, rate_limiter)
    @collector = collector
    @rate_limiter = rate_limiter
  end

  def handle_fork
  end
end

Aikido::Zen.instance_variable_set(
  :@detached_agent,
  FakeDetachedAgent.new(Aikido::Zen::Collector.new, Aikido::Zen::RateLimiter.new)
)

# Silence warnings that result from loading HTTPClient.
ActiveSupport::Testing::Stream.quietly { require "webmock" }
# For the HTTP adapters shipped with WebMock by default, requiring webmock first
# and then requiring our sinks works great (because we patch the namespace that
# webmock patched, so we run our code and then delegate to it).
#
# However, HTTPX does things… differently, and if we don't require things in
# _just_ the correct order, the webmock adapter won't be set up correctly.
require "httpx"
require "webmock/minitest"
require "support/sinks"

require_relative "support/puma"
require_relative "support/uri_origin"
require_relative "support/fake_rails_app"
require_relative "support/http_connection_tracking_assertions"
require_relative "support/rate_limiting_assertions"
require_relative "support/sink_attack_helpers"
require_relative "support/worker_helpers"

# Utility proc that does nothing.
NOOP = ->(*args, **opts) {}

class ActiveSupport::TestCase
  self.file_fixture_path = "test/fixtures"

  # Reset any global state before each test
  setup do
    Aikido::Zen.instance_variable_set(:@info, nil)
    Aikido::Zen.instance_variable_set(:@agent, nil)
    Aikido::Zen.instance_variable_set(:@config, nil)

    collector = Aikido::Zen::Collector.new

    Aikido::Zen.instance_variable_set(:@collector, collector)
    Aikido::Zen.detached_agent.instance_variable_set(:@collector, collector)

    Aikido::Zen.instance_variable_set(:@runtime_settings, nil)
    Aikido::Zen.detached_agent.instance_variable_set(:@rate_limiter, Aikido::Zen::RateLimiter.new)

    Aikido::Zen.current_context = nil

    Aikido::Zen.singleton_class.remove_method(:track_scan)
    Aikido::Zen.singleton_class.define_method(:track_scan) do |scan|
      collector.track_scan(scan)

      if scan.attack?
        attack = scan.attack
        collector.track_attack(attack)
        raise attack
      end
    end

    @_old_sinks_registry = Aikido::Zen::Sinks.registry.dup
    Aikido::Zen::Sinks.registry.clear

    Aikido::Zen::Sinks::ActionController.instance_variable_set(:@block_request_checker, nil)

    WebMock.reset!
  end

  teardown do
    # In case any test starts the agent background thread as a side effect, this
    # should make sure we're cleaning things up.
    Aikido::Zen.stop!

    Aikido::Zen::Sinks.registry.replace(@_old_sinks_registry)
  end

  # Reset the routes in the test app defined in test/support/fake_rails_app to
  # avoid any leaks between tests.
  setup do
    new_routes = ActionDispatch::Routing::RouteSet.new
    Rails.application.instance_variable_set(:@routes, new_routes)

    # Also reset the reference to the Rails router, so we pick up the new
    # RouteSet object in each test.
    Aikido::Zen::Rails.instance_variable_set(:@router, nil)
  end

  # Capture log output and make it testable
  setup do
    @log_output = StringIO.new
    Aikido::Zen.config.debugging = true
    Aikido::Zen.config.logger = Aikido::Zen.config.logger.reopen(@log_output)
  end

  # rubocop:disable Style/OptionalArguments
  def assert_logged(level = nil, pattern)
    @log_output.rewind

    pattern = /#{pattern}/ unless pattern.is_a?(Regexp)

    lines = @log_output.readlines.map(&:chomp)
    match_level = level.to_s.upcase if level

    reason = "no #{level.inspect if level} log message " +
      "matches #{pattern.inspect}. ".squeeze("\s") +
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

  # Checks that all the data in {subset} is part of the {container} hash.
  #
  # @example
  #   data = {name: "Alice", email: "alice@example.com", id: 3}
  #   assert_hash_subset_of data, {name: "Alice", id: 3}
  def assert_hash_subset_of(container, subset)
    assert_equal container.slice(*subset.keys), subset
  end

  def skip_if_ruby_lower_than(expected_ruby_version)
    if expected_ruby_version > RUBY_VERSION
      skip "Skipping test #{__method__} because unexpected ruby version (#{RUBY_VERSION} < #{expected_ruby_version})"
    end
  end

  module StubsCurrentContext
    # Override in tests to return the desired stub.
    def current_context
      @current_context ||= Aikido::Zen::Context.from_rack_env({})
    end

    def with_context(context)
      old_context = Aikido::Zen.current_context
      Aikido::Zen.current_context = context
      yield
    ensure
      Aikido::Zen.current_context = old_context
    end

    def self.included(base)
      base.setup { Aikido::Zen.current_context = current_context }
      base.teardown { Aikido::Zen.current_context = nil }
    end
  end
end
