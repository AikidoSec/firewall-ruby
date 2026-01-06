# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RuntimeSettingsTest < ActiveSupport::TestCase
  setup do
    @settings = Aikido::Zen::RuntimeSettings.new
  end

  test "building from a JSON response" do
    assert @settings.update_from_runtime_config_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIPAddresses" => [],
      "receivedAnyStats" => false,
      "block" => true
    })

    assert_equal Time.utc(2024, 5, 31, 16, 8, 37), @settings.updated_at
    assert_equal 60, @settings.heartbeat_interval
    assert_equal Aikido::Zen::RuntimeSettings::Endpoints.new, @settings.endpoints
    assert_equal [], @settings.blocked_user_ids
    assert_equal Aikido::Zen::RuntimeSettings::IPSet.new, @settings.allowed_ips
    assert_equal false, @settings.received_any_stats
    assert_equal true, @settings.blocking_mode
  end

  test "building from a JSON response without the block key" do
    assert @settings.update_from_runtime_config_json({
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
    assert_equal Aikido::Zen::RuntimeSettings::IPSet.new, @settings.allowed_ips
    assert_equal false, @settings.received_any_stats
    assert_nil @settings.blocking_mode
  end

  test "#update_from_runtime_config_json should return true or false in case the settings were or no updated" do
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

    assert @settings.update_from_runtime_config_json(payload)
    refute @settings.update_from_runtime_config_json(payload)
    refute @settings.update_from_runtime_config_json(payload)

    payload["configUpdatedAt"] = 1726354453000

    assert @settings.update_from_runtime_config_json(payload)
    refute @settings.update_from_runtime_config_json(payload)
  end

  test "#allowed_ips lets you use individual addresses" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["1.2.3.4", "2.3.4.5"]
    })

    assert_includes @settings.allowed_ips, "1.2.3.4"
    assert_includes @settings.allowed_ips, "2.3.4.5"
    refute_includes @settings.allowed_ips, "3.4.5.6"
  end

  test "#allowed_ips lets you pass CIDR blocks" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["10.0.0.0/31", "1.1.1.1"]
    })

    assert_includes @settings.allowed_ips, "1.1.1.1"
    assert_includes @settings.allowed_ips, "10.0.0.0"
    assert_includes @settings.allowed_ips, "10.0.0.1"
    refute_includes @settings.allowed_ips, "10.0.0.2"
  end

  test "#allowed_ips lets you use individual IPv6 addresses" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["2001:db8::1", "2001:db8::2"]
    })

    assert_includes @settings.allowed_ips, "2001:db8::1"
    assert_includes @settings.allowed_ips, "2001:db8::2"
    refute_includes @settings.allowed_ips, "2001:db8::3"
  end

  test "#allowed_ips lets you pass IPv6 CIDR blocks" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["2001:db8::/127", "2001:db8::100"]
    })

    assert_includes @settings.allowed_ips, "2001:db8::"
    assert_includes @settings.allowed_ips, "2001:db8::1"
    assert_includes @settings.allowed_ips, "2001:db8::100"
    refute_includes @settings.allowed_ips, "2001:db8::2"
  end

  test "parsing endpoint data" do
    assert @settings.update_from_runtime_config_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [
        {
          "method" => "GET",
          "route" => "/",
          "forceProtectionOff" => true,
          "graphql" => nil,
          "allowedIPAddresses" => [],
          "rateLimiting" => {
            "enabled" => false,
            "maxRequests" => 100,
            "windowSizeInMS" => 60000
          }
        },
        {
          "method" => "GET",
          "route" => "/admin",
          "forceProtectionOff" => false,
          "graphql" => nil,
          "allowedIPAddresses" => [
            "10.0.0.0/8"
          ],
          "rateLimiting" => {
            "enabled" => false,
            "maxRequests" => 100,
            "windowSizeInMS" => 60000
          }
        },
        {
          "method" => "POST",
          "route" => "/users/sign_in",
          "forceProtectionOff" => false,
          "graphql" => nil,
          "allowedIPAddresses" => [],
          "rateLimiting" => {
            "enabled" => true,
            "maxRequests" => 10,
            "windowSizeInMS" => 60000
          }
        }
      ],
      "blockedUserIds" => [],
      "allowedIPAddresses" => [],
      "receivedAnyStats" => false
    })

    root_settings = @settings.endpoints[build_route("GET", "/")]
    auth_settings = @settings.endpoints[build_route("POST", "/users/sign_in")]
    admin_settings = @settings.endpoints[build_route("GET", "/admin")]

    refute root_settings.protected?
    assert auth_settings.protected?
    assert admin_settings.protected?

    assert_empty root_settings.allowed_ips
    assert_empty auth_settings.allowed_ips
    assert_includes admin_settings.allowed_ips, IPAddr.new("10.0.0.0/8")

    refute root_settings.rate_limiting.enabled?
    assert auth_settings.rate_limiting.enabled?
    refute admin_settings.rate_limiting.enabled?
  end

  test "endpoints without an explicit config get a reasonable default value" do
    assert @settings.update_from_runtime_config_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIPAddresses" => [],
      "receivedAnyStats" => false
    })

    root = build_route("GET", "/")
    root_settings = @settings.endpoints[root]

    assert root_settings.protected?
    assert_empty root_settings.allowed_ips
    refute root_settings.rate_limiting.enabled?
  end

  def build_route(verb, path)
    Aikido::Zen::Route.new(verb: verb, path: path)
  end
end
