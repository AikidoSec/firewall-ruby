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

  test "building from a JSON response notifies the agent" do
    agent = Minitest::Mock.new
    agent.expect :updated_settings!, nil

    Aikido::Zen.stub(:agent, agent) do
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

      assert_mock agent
    end
  end

  test "observers are only notified if the settings have changed" do
    agent = Minitest::Mock.new

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

    Aikido::Zen.stub(:agent, agent) do
      agent.expect :updated_settings!, nil
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)

      payload["configUpdatedAt"] = 1726354453000

      agent.expect :updated_settings!, nil
      @settings.update_from_json(payload)
      @settings.update_from_json(payload)
    end

    assert_mock agent
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

  test "parsing endpoint data" do
    @settings.update_from_json({
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
