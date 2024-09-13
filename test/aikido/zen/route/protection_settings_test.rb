# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Route::ProtectionSettingsTest < ActiveSupport::TestCase
  test "default settings" do
    settings = Aikido::Zen::Route::ProtectionSettings.none

    assert settings.protected?
    assert_empty settings.allowed_ips
  end

  test ".from_json parses the correct fields" do
    data = {
      "forceProtectionOff" => false,
      "allowedIPAddresses" => ["1.1.1.1", "2.2.2.2"],
      "rateLimiting" => {
        "enabled" => false, "maxRequests" => 1000, "windowSizeInMS" => 300000
      }
    }

    settings = Aikido::Zen::Route::ProtectionSettings.from_json(data)

    assert settings.protected?
    refute_empty settings.allowed_ips
  end

  test ".from_json ignores extra fields in the Hash" do
    data = {
      "route" => "/users/:id",
      "method" => "GET",
      "forceProtectionOff" => false,
      "allowedIPAddresses" => ["1.1.1.1", "2.2.2.2"],
      "rateLimiting" => {
        "enabled" => false, "maxRequests" => 1000, "windowSizeInMS" => 300000
      }
    }

    settings = Aikido::Zen::Route::ProtectionSettings.from_json(data)
    assert_kind_of Aikido::Zen::Route::ProtectionSettings, settings
  end

  test ".from_json parses IPv4 addresses" do
    data = build_api_response("allowedIPAddresses" => ["1.1.1.1", "2.2.2.2"])
    settings = Aikido::Zen::Route::ProtectionSettings.from_json(data)

    assert_includes settings.allowed_ips, IPAddr.new("1.1.1.1")
    assert_includes settings.allowed_ips, IPAddr.new("2.2.2.2")
  end

  test ".from_json parses IPv4 CIDR blocks" do
    data = build_api_response("allowedIPAddresses" => ["10.0.0.0/8"])
    settings = Aikido::Zen::Route::ProtectionSettings.from_json(data)

    assert_includes settings.allowed_ips, IPAddr.new("10.0.0.0/8")
  end

  test ".from_json parses abbreviated IPv6 addresses" do
    data = build_api_response("allowedIPAddresses" => ["::1"])
    settings = Aikido::Zen::Route::ProtectionSettings.from_json(data)

    assert_includes settings.allowed_ips, IPAddr.new("::1")
  end

  test ".from_json parses fully qualified IPv6 addresses" do
    data = build_api_response("allowedIPAddresses" => ["2001:db8:85a3::8a2e:370:7334"])
    settings = Aikido::Zen::Route::ProtectionSettings.from_json(data)

    assert_includes settings.allowed_ips, IPAddr.new("2001:db8:85a3::8a2e:370:7334")
  end

  test ".from_json parses IPv6 CIDR blocks" do
    data = build_api_response("allowedIPAddresses" => ["2001:db8::0000/32"])
    settings = Aikido::Zen::Route::ProtectionSettings.from_json(data)

    assert_includes settings.allowed_ips, IPAddr.new("2001:db8::0000/32")
  end

  test ".from_json raises if given an invalid IP address" do
    data = build_api_response("allowedIPAddresses" => ["nope"])

    assert_raises IPAddr::InvalidAddressError do
      Aikido::Zen::Route::ProtectionSettings.from_json(data)
    end
  end

  def build_api_response(overrides = {})
    {
      "forceProtectionOff" => false,
      "allowedIPAddresses" => [],
      "rateLimiting" => {
        "enabled" => false, "maxRequests" => 1000, "windowSizeInMS" => 300000
      }
    }.merge(overrides)
  end
end
