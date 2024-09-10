# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RuntimeSettingsTest < ActiveSupport::TestCase
  setup do
    @settings = Aikido::Zen::RuntimeSettings.new
  end

  test "building from a JSON response" do
    @settings.update_from_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIPAddresses" => [],
      "receivedAnyStats" => false
    })

    assert_equal Time.utc(2024, 5, 31, 16, 8, 37), @settings.updated_at
    assert_equal 60, @settings.heartbeat_interval
    assert_equal Aikido::Zen::RuntimeSettings::Endpoints.new, @settings.endpoints
    assert_equal [], @settings.blocked_user_ids
    assert_equal Aikido::Zen::RuntimeSettings::IPSet.new, @settings.skip_protection_for_ips
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
      "allowedIPAddresses" => [],
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
      "allowedIPAddresses" => [],
      "receivedAnyStats" => false
    }

    assert_difference "observer_notifications", +1 do
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
    end

    payload["configUpdatedAt"] = 1726354453000

    assert_difference "observer_notifications", +1 do
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
    end
  end

  test "#skip_protection_for_ips lets you use individual addresses" do
    @settings.update_from_json({
      "allowedIPAddresses" => ["1.2.3.4", "2.3.4.5"]
    })

    assert_includes @settings.skip_protection_for_ips, "1.2.3.4"
    assert_includes @settings.skip_protection_for_ips, "2.3.4.5"
    refute_includes @settings.skip_protection_for_ips, "3.4.5.6"
  end

  test "#skip_protection_for_ips lets you pass CIDR blocks" do
    @settings.update_from_json({
      "allowedIPAddresses" => ["10.0.0.0/31", "1.1.1.1"]
    })

    assert_includes @settings.skip_protection_for_ips, "1.1.1.1"
    assert_includes @settings.skip_protection_for_ips, "10.0.0.0"
    assert_includes @settings.skip_protection_for_ips, "10.0.0.1"
    refute_includes @settings.skip_protection_for_ips, "10.0.0.2"
  end
end
