# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Route::ProtectionSettingsTest < ActiveSupport::TestCase
  test "default settings" do
    settings = Aikido::Zen::Route::ProtectionSettings.none

    assert settings.protected?
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
end
