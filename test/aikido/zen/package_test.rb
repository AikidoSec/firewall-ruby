# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::PackageTest < ActiveSupport::TestCase
  test "reports #name and #version" do
    pkg = Aikido::Zen::Package.new("test", Gem::Version.new("1.0.0"))

    assert_equal "test", pkg.name
    assert_equal Gem::Version.new("1.0.0"), pkg.version
  end

  test "is considered supported? if we loaded a sink with the same name" do
    sinks = {"test" => Object.new}
    pkg = Aikido::Zen::Package.new("test", Gem::Version.new("1.0.0"), sinks)

    assert pkg.supported?
  end

  test "is not considered supported if no sink was registered with the same name" do
    sinks = {}
    pkg = Aikido::Zen::Package.new("test", Gem::Version.new("1.0.0"), sinks)

    refute pkg.supported?
  end

  test "#as_json provides the expected serialization" do
    pkg = Aikido::Zen::Package.new("test", Gem::Version.new("1.0.0"))

    assert_equal({"test" => "1.0.0"}, pkg.as_json)
  end
end
