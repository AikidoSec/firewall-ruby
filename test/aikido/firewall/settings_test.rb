# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::SettingsTest < ActiveSupport::TestCase
  setup do
    @settings = Aikido::Firewall::Settings.new
  end

  test "building from a JSON response" do
    @settings.update_from_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIpAddresses" => [],
      "receivedAnyStats" => false
    })

    assert_equal Time.utc(2024, 5, 31, 16, 8, 37), @settings.updated_at
    assert_equal 60, @settings.heartbeat_interval
    assert_equal [], @settings.endpoints
    assert_equal [], @settings.blocked_user_ids
    assert_equal [], @settings.allowed_ip_addresses
    assert_equal false, @settings.received_any_stats
  end

  test "building from a JSON response notifies observers" do
    observer_notified = false
    observer = ->(settings) { observer_notified = true }

    @settings.add_observer(observer, :call)

    @settings.update_from_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIpAddresses" => [],
      "receivedAnyStats" => false
    })

    assert observer_notified
  end

  test "observers are only notified if the settings have changed" do
    observer_notifications = 0
    observer = ->(settings) { observer_notifications += 1 }

    @settings.add_observer(observer, :call)

    payload = {
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIpAddresses" => [],
      "receivedAnyStats" => false
    }

    assert_changes -> { observer_notifications }, from: 0, to: 1 do
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
    end

    payload["configUpdatedAt"] = 1726354453000

    assert_changes -> { observer_notifications }, from: 1, to: 2 do
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
    end
  end
end
