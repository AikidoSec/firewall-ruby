# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RuntimeSettingsTest < ActiveSupport::TestCase
  setup do
    @settings = Aikido::Zen::RuntimeSettings.new
  end

  test "#update_from_runtime_config_json from a JSON response" do
    assert @settings.update_from_runtime_config_json({
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIPAddresses" => [],
      "receivedAnyStats" => false,
      "block" => true,
      "blockNewOutgoingRequests" => true,
      "domains" => [
        {
          "hostname" => "safe.example.com",
          "mode" => "allow"
        },
        {
          "hostname" => "evil.example.com",
          "mode" => "block"
        }
      ]
    })

    assert_equal Time.utc(2024, 5, 31, 16, 8, 37), @settings.updated_at
    assert_equal 60, @settings.heartbeat_interval
    assert_equal Aikido::Zen::RuntimeSettings::Endpoints.new, @settings.endpoints
    assert_equal [], @settings.blocked_user_ids
    assert_equal Aikido::Zen::RuntimeSettings::IPSet.new, @settings.bypassed_ips
    assert_equal false, @settings.received_any_stats
    assert_equal true, @settings.blocking_mode
    assert_equal true, @settings.block_new_outbound

    assert_equal 2, @settings.domains.size
    assert_includes @settings.domains, "safe.example.com"
    assert_includes @settings.domains, "evil.example.com"

    safe_domain = @settings.domains["safe.example.com"]
    assert_kind_of Aikido::Zen::RuntimeSettings::DomainSettings, safe_domain
    assert_equal :allow, safe_domain.mode

    evil_domain = @settings.domains["evil.example.com"]
    assert_kind_of Aikido::Zen::RuntimeSettings::DomainSettings, evil_domain
    assert_equal :block, evil_domain.mode

    new_domain = @settings.domains["new.example.com"]
    assert_kind_of Aikido::Zen::RuntimeSettings::DomainSettings, new_domain
    assert_equal :block, new_domain.mode
  end

  test "#update_from_runtime_config_json from a JSON response without the block key" do
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
    assert_equal Aikido::Zen::RuntimeSettings::IPSet.new, @settings.bypassed_ips
    assert_equal false, @settings.received_any_stats
    assert_nil @settings.blocking_mode
  end

  test "#update_from_runtime_config_json should return true or false indicating whether the settings were updated" do
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

  test "#update_from_runtime_config_json populates excluded_user_ids_from_rate_limiting" do
    @settings.update_from_runtime_config_json({
      "excludedUserIdsFromRateLimiting" => ["user1", "user2"]
    })

    assert @settings.user_excluded_from_rate_limiting?("user1")
    assert @settings.user_excluded_from_rate_limiting?("user2")
    refute @settings.user_excluded_from_rate_limiting?("user3")
  end

  test "#user_excluded_from_rate_limiting? coerces ids to strings" do
    @settings.update_from_runtime_config_json({
      "excludedUserIdsFromRateLimiting" => [42]
    })

    assert @settings.user_excluded_from_rate_limiting?(42)
    assert @settings.user_excluded_from_rate_limiting?("42")
  end

  test "#user_excluded_from_rate_limiting? returns false for nil" do
    refute @settings.user_excluded_from_rate_limiting?(nil)
  end

  test "#update_from_runtime_config_json replaces the excluded user ids set" do
    @settings.update_from_runtime_config_json({
      "excludedUserIdsFromRateLimiting" => ["user1", "user2"]
    })
    @settings.update_from_runtime_config_json({
      "excludedUserIdsFromRateLimiting" => ["user3"]
    })

    refute @settings.user_excluded_from_rate_limiting?("user1")
    refute @settings.user_excluded_from_rate_limiting?("user2")
    assert @settings.user_excluded_from_rate_limiting?("user3")
  end

  test "#update_from_runtime_config_json with an empty array clears the excluded user ids" do
    @settings.update_from_runtime_config_json({
      "excludedUserIdsFromRateLimiting" => ["user1"]
    })
    @settings.update_from_runtime_config_json({
      "excludedUserIdsFromRateLimiting" => []
    })

    refute @settings.user_excluded_from_rate_limiting?("user1")
  end

  test "#bypassed_ips lets you use individual addresses" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["1.2.3.4", "2.3.4.5"]
    })

    assert_includes @settings.bypassed_ips, "1.2.3.4"
    assert_includes @settings.bypassed_ips, "2.3.4.5"
    refute_includes @settings.bypassed_ips, "3.4.5.6"

    assert_includes @settings.bypassed_ips, "::ffff:1.2.3.4"
    assert_includes @settings.bypassed_ips, "::ffff:2.3.4.5"
    refute_includes @settings.bypassed_ips, "::ffff:3.4.5.6"
  end

  test "#bypassed_ips lets you pass CIDR blocks" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["10.0.0.0/31", "1.1.1.1"]
    })

    assert_includes @settings.bypassed_ips, "1.1.1.1"
    assert_includes @settings.bypassed_ips, "10.0.0.0"
    assert_includes @settings.bypassed_ips, "10.0.0.1"
    refute_includes @settings.bypassed_ips, "10.0.0.2"

    assert_includes @settings.bypassed_ips, "::ffff:1.1.1.1"
    assert_includes @settings.bypassed_ips, "::ffff:10.0.0.0"
    assert_includes @settings.bypassed_ips, "::ffff:10.0.0.1"
    refute_includes @settings.bypassed_ips, "::ffff:10.0.0.2"
    assert_includes @settings.bypassed_ips, "::ffff:10.0.0.1"
  end

  test "#bypassed_ips lets you use individual IPv6 addresses" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["2001:db8::1", "2001:db8::2"]
    })

    assert_includes @settings.bypassed_ips, "2001:db8::1"
    assert_includes @settings.bypassed_ips, "2001:db8::2"
    refute_includes @settings.bypassed_ips, "2001:db8::3"
  end

  test "#bypassed_ips lets you pass IPv6 CIDR blocks" do
    assert @settings.update_from_runtime_config_json({
      "allowedIPAddresses" => ["2001:db8::/127", "2001:db8::100"]
    })

    assert_includes @settings.bypassed_ips, "2001:db8::"
    assert_includes @settings.bypassed_ips, "2001:db8::1"
    assert_includes @settings.bypassed_ips, "2001:db8::100"
    refute_includes @settings.bypassed_ips, "2001:db8::2"
  end

  test "parses endpoint data" do
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

  test "#update_from_runtime_firewall_lists_json from an empty JSON response" do
    @settings.update_from_runtime_firewall_lists_json({})

    assert_equal [], @settings.allowed_ip_lists
    assert_equal [], @settings.blocked_ip_lists
    assert_nil @settings.blocked_user_agent_regexp
    assert_nil @settings.monitored_user_agent_regexp
    assert_equal [], @settings.user_agent_details
  end

  test "#update_from_runtime_firewall_lists_json from a JSON response" do
    @settings.update_from_runtime_firewall_lists_json({
      "blockedIPAddresses" => [
        {
          "key" => "key1",
          "source" => "source1",
          "description" => "description1",
          "ips" => [
            "1.4.9.0/24",
            "1.173.94.92/30",
            "2.16.20.0/23",
            "2.16.53.0/24",
            "2.16.103.0/24"
          ]
        }
      ],
      "allowedIPAddresses" => [
        {
          "key" => "key2",
          "source" => "source2",
          "description" => "description2",
          "ips" => [
            "2.63.192.0/19",
            "2.63.240.0/20",
            "2.92.0.0/14",
            "5.1.41.0/24",
            "5.1.47.0/24",
            "5.1.48.0/21",
            "5.2.32.0/19",
            "5.3.0.0/16"
          ]
        },
        {
          "key" => "key3",
          "source" => "source3",
          "description" => "description3",
          "ips" => [
            "5.8.8.0/21",
            "5.8.16.0/23",
            "5.8.19.0/24"
          ]
        }
      ],
      "blockedUserAgents" => "Applebot-Extended|CCBot|ClaudeBot|Google-Extended|GPTBot|meta-externalagent|anthropic-ai|AdsBot-Google|Mediapartners-Google|Mediapartners \\(Googlebot\\)|Google-Adwords",
      "monitoredUserAgents" => "ChatGPT-User|Meta-ExternalFetcher|Claude-Web|GitHubCopilotChat|Claude-User",
      "userAgentDetails" => [
        {"key" => "applebot_extended", "pattern" => "Applebot-Extended"},
        {"key" => "ccbot", "pattern" => "CCBot"},
        {"key" => "claudebot", "pattern" => "ClaudeBot"},
        {}, # Skipped; no key or pattern
        {"key" => "key"}, # Skipped; no pattern
        {"pattern" => "pattern"}, # Skipped; no key
        {"key" => "key", "pattern" => "abc("}, # Skipped; invalid regexp
        {"key" => "google_extended", "pattern" => "Google-Extended"},
        {"key" => "gptbot", "pattern" => "GPTBot"},
        {"key" => "meta_externalagent", "pattern" => "meta-externalagent"},
        {"key" => "anthropic_ai", "pattern" => "anthropic-ai"},
        {"key" => "chatgpt_user", "pattern" => "ChatGPT-User"},
        {"key" => "meta_externalfetcher", "pattern" => "Meta-ExternalFetcher"},
        {"key" => "claude_web", "pattern" => "Claude-Web"},
        {"key" => "githubcopilotchat", "pattern" => "GitHubCopilotChat"},
        {"key" => "claude_user", "pattern" => "Claude-User"},
        {"key" => "adsbot_google", "pattern" => "AdsBot-Google"},
        {"key" => "mediapartners_google", "pattern" => "Mediapartners-Google"},
        {"key" => "mediapartners_googlebot", "pattern" => "Mediapartners \\(Googlebot\\)"},
        {"key" => "google_adwords", "pattern" => "Google-Adwords"}
      ]
    })

    assert_kind_of Array, @settings.blocked_ip_lists
    assert 1, @settings.blocked_ip_lists.size
    @settings.blocked_ip_lists.each_index do |index|
      assert_equal "key#{index + 1}", @settings.blocked_ip_lists[index].key
      assert_equal "source#{index + 1}", @settings.blocked_ip_lists[index].source
      assert_equal "description#{index + 1}", @settings.blocked_ip_lists[index].description
    end

    assert_kind_of Array, @settings.allowed_ip_lists
    assert 2, @settings.allowed_ip_lists.size
    @settings.allowed_ip_lists.each_index do |index|
      assert_equal "key#{index + 2}", @settings.allowed_ip_lists[index].key
      assert_equal "source#{index + 2}", @settings.allowed_ip_lists[index].source
      assert_equal "description#{index + 2}", @settings.allowed_ip_lists[index].description
    end

    assert_kind_of Regexp, @settings.blocked_user_agent_regexp
    assert_kind_of Regexp, @settings.monitored_user_agent_regexp

    assert_kind_of Array, @settings.user_agent_details
    assert 16, @settings.user_agent_details.size
    @settings.user_agent_details.each do |record|
      assert_kind_of String, record[:key]
      assert_kind_of Regexp, record[:pattern]
    end
  end

  test "#user_agent_keys returns an empty array when the user agent is nil" do
    assert_equal [], @settings.user_agent_keys(nil)
  end

  def build_route(verb, path)
    Aikido::Zen::Route.new(verb: verb, path: path)
  end
end
