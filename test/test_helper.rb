# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "aikido/firewall"
require "minitest/autorun"
require "minitest/stub_const"
require "pathname"
require "debug"

class Minitest::Test
  # Add declarative tests like ActiveSupport adds, because they read nicer.
  def self.test(name, &block)
    test_name = :"test_#{name.gsub(/\s+/, "_")}"
    raise "#{test_name} is already defined in #{self}" if method_defined?(test_name)

    if block
      define_method(test_name, &block)
    else
      define_method(test_name) { flunk "No implementation provided for #{name}" }
    end
  end

  @@_setup_callbacks = []
  @@_teardown_callbacks = []

  def self.setup(&block)
    @@_setup_callbacks << block
  end

  def self.teardown(&block)
    @@_teardown_callbacks << block
  end

  def before_setup
    super
    Array(@@_setup_callbacks).each { |block| instance_exec(&block) }
  end

  def after_teardown
    Array(@@_teardown_callbacks).each { |block| instance_exec(&block) }
  rescue => err
    failures << Minitest::UnexpectedError.new(err)
  ensure
    super
  end

  # Reset any global state before each test
  setup do
    Aikido::Agent.instance_variable_set(:@config, nil)
    Aikido::Firewall.instance_variable_set(:@settings, nil)
  end

  # @return [Pathname] the given file path within test/fixtures.
  def file_fixture(relative_path)
    Pathname("test/fixtures").join(relative_path)
  end
end
