# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::SettingsTest < Minitest::Test
  setup do
    @settings = Aikido::Firewall::Settings.new
  end

  test "updating from a JSON response" do
    refute @settings.loaded?

    @settings.update_from_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIpAddresses" => [],
      "receivedAnyStats" => false
    })

    assert @settings.loaded?
    assert_equal Time.utc(2024, 5, 31, 16, 8, 37), @settings.updated_at
    assert_equal 60, @settings.heartbeat_interval
    assert_equal [], @settings.endpoints
    assert_equal [], @settings.blocked_user_ids
    assert_equal [], @settings.allowed_ip_addresses
    assert_equal false, @settings.received_any_stats
  end
end
