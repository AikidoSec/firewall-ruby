# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "aikido/firewall"
require "minitest/autorun"
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

  # @return [Pathname] the given file path within test/fixtures.
  def file_fixture(relative_path)
    Pathname("test/fixtures").join(relative_path)
  end
end
