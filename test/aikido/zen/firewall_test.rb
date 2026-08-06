# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::FirewallTest < ActiveSupport::TestCase
  setup do
    @firewall = Aikido::Zen::Firewall.new
  end

  test "#update_from_json from an empty JSON response" do
    @firewall.update_from_json({})

    assert_equal [], @firewall.allowed_ip_lists
    assert_equal [], @firewall.blocked_ip_lists
    assert_nil @firewall.blocked_user_agent_regexp
    assert_nil @firewall.monitored_user_agent_regexp
    assert_equal [], @firewall.user_agent_details
  end

  test "#update_from_json from a JSON response" do
    @firewall.update_from_json({
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

    assert_kind_of Array, @firewall.blocked_ip_lists
    assert_equal 1, @firewall.blocked_ip_lists.size
    @firewall.blocked_ip_lists.each_index do |index|
      assert_equal "key#{index + 1}", @firewall.blocked_ip_lists[index].key
      assert_equal "source#{index + 1}", @firewall.blocked_ip_lists[index].source
      assert_equal "description#{index + 1}", @firewall.blocked_ip_lists[index].description
    end

    assert_kind_of Array, @firewall.allowed_ip_lists
    assert_equal 2, @firewall.allowed_ip_lists.size
    @firewall.allowed_ip_lists.each_index do |index|
      assert_equal "key#{index + 2}", @firewall.allowed_ip_lists[index].key
      assert_equal "source#{index + 2}", @firewall.allowed_ip_lists[index].source
      assert_equal "description#{index + 2}", @firewall.allowed_ip_lists[index].description
    end

    assert_kind_of Regexp, @firewall.blocked_user_agent_regexp
    assert_kind_of Regexp, @firewall.monitored_user_agent_regexp

    assert_kind_of Array, @firewall.user_agent_details
    assert_equal 16, @firewall.user_agent_details.size
    @firewall.user_agent_details.each do |record|
      assert_kind_of String, record[:key]
      assert_kind_of Regexp, record[:pattern]
    end
  end

  test "#user_agent_keys returns an empty array when the user agent is nil" do
    assert_equal [], @firewall.user_agent_keys(nil)
  end
end
