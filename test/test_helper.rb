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

  # Reset any global state before each test
  setup do
    Aikido::Agent.instance_variable_set(:@config, nil)
    Aikido::Firewall.instance_variable_set(:@settings, nil)

    WebMock.reset!
  end
end
