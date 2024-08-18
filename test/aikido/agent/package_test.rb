# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::PackageTest < ActiveSupport::TestCase
  Package = Aikido::Agent::Package

  test "reports #name and #version" do
    pkg = Package.new("test", Gem::Version.new("1.0.0"))

    assert_equal "test", pkg.name
    assert_equal Gem::Version.new("1.0.0"), pkg.version
  end

  test "is considered supported? if we loaded a sink with the same name" do
    sinks = {"test" => Object.new}
    pkg = Package.new("test", Gem::Version.new("1.0.0"), sinks)

    assert pkg.supported?
  end

  test "is not considered supported if no sink was registered with the same name" do
    sinks = {}
    pkg = Package.new("test", Gem::Version.new("1.0.0"), sinks)

    refute pkg.supported?
  end

  test "#as_json provides the expected serialization" do
    pkg = Package.new("test", Gem::Version.new("1.0.0"))

    assert_equal({"test" => "1.0.0"}, pkg.as_json)
  end
end
