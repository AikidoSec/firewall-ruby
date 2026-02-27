# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RuntimeSettings::DomainSettingsTest < ActiveSupport::TestCase
  test "create domain settings" do
    domain_settings = Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: :block)

    refute_nil domain_settings
    assert_kind_of Aikido::Zen::RuntimeSettings::DomainSettings, domain_settings
  end

  test "create domain settings from JSON" do
    domain_settings = Aikido::Zen::RuntimeSettings::DomainSettings.from_json({
      "hostname" => "example.com",
      "mode" => "allow"
    })

    refute_nil domain_settings
    assert_kind_of Aikido::Zen::RuntimeSettings::DomainSettings, domain_settings
  end

  test "create domain settings with invalid mode raises ArgumentError" do
    assert_raises(ArgumentError) do
      Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: nil)
    end

    assert_raises(ArgumentError) do
      Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: :invalid)
    end

    assert_raises(ArgumentError) do
      Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: "invalid")
    end
  end

  test "create domain settings with invalid mode from JSON raises ArgumentError" do
    assert_raises(ArgumentError) do
      Aikido::Zen::RuntimeSettings::DomainSettings.from_json({
        "hostname" => "example.com",
        "mode" => nil
      })
    end

    assert_raises(ArgumentError) do
      Aikido::Zen::RuntimeSettings::DomainSettings.from_json({
        "hostname" => "example.com",
        "mode" => "invalid"
      })
    end
  end

  test "#mode returns the mode" do
    blocked_domain_settings = Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: :block)

    assert_equal :block, blocked_domain_settings.mode

    allowed_domain_settings = Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: :allow)

    assert_equal :allow, allowed_domain_settings.mode
  end

  test "#block? returns true for blocked domains" do
    domain_settings = Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: :block)

    assert domain_settings.block?
  end

  test "#block? returns false for allowed domains" do
    domain_settings = Aikido::Zen::RuntimeSettings::DomainSettings.new(mode: :allow)

    refute domain_settings.block?
  end

  test "#block? returns true for unknown domains" do
    domain_settings = Aikido::Zen::RuntimeSettings::DomainSettings.none

    assert domain_settings.block?
  end
end
