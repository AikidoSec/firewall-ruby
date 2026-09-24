# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::FirewallTest < ActiveSupport::TestCase
  setup do
    @ip_lists_directory = Dir.mktmpdir("firewall_test_ip_lists")
    Aikido::Zen.config.ip_lists_dir = @ip_lists_directory
    @firewall = Aikido::Zen::Firewall.new
  end

  teardown do
    FileUtils.remove_entry(@ip_lists_directory)
  end

  test "#initialize creates ip_lists_dir if it does not exist yet" do
    nested_dir = File.join(@ip_lists_directory, "nested")

    Aikido::Zen::Firewall.new(ip_lists_dir: nested_dir)

    assert Dir.exist?(nested_dir)
  end

  test "#update_user_agents_from_json and #update_ip_lists_from_json handle an empty JSON response" do
    @firewall.update_user_agents_from_json({})
    @firewall.update_ip_lists_from_json({})

    assert @firewall.allowed_ip_lists.empty?
    assert @firewall.blocked_ip_lists.empty?
    assert_nil @firewall.blocked_user_agent_regexp
    assert_nil @firewall.monitored_user_agent_regexp
    assert_equal [], @firewall.user_agent_details
  end

  test "#update_user_agents_from_json and #update_ip_lists_from_json handle a JSON response" do
    data = {
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
    }

    @firewall.update_user_agents_from_json(data)
    @firewall.update_ip_lists_from_json(data)

    assert_kind_of Aikido::Zen::Firewall::IPLists, @firewall.blocked_ip_lists
    refute @firewall.blocked_ip_lists.empty?

    blocked_matches = @firewall.matching_blocked_ip_lists("1.4.9.1")
    assert_equal 1, blocked_matches.size
    assert_equal "key1", blocked_matches.first.key
    assert_equal "source1", blocked_matches.first.source
    assert_equal "description1", blocked_matches.first.description

    assert_kind_of Aikido::Zen::Firewall::IPLists, @firewall.allowed_ip_lists
    refute @firewall.allowed_ip_lists.empty?
    assert @firewall.allowed_ip?("2.63.192.1")
    assert @firewall.allowed_ip?("5.8.8.1")
    refute @firewall.allowed_ip?("8.8.8.8")

    assert_kind_of Regexp, @firewall.blocked_user_agent_regexp
    assert_kind_of Regexp, @firewall.monitored_user_agent_regexp

    assert_kind_of Array, @firewall.user_agent_details
    assert_equal 16, @firewall.user_agent_details.size
    @firewall.user_agent_details.each do |record|
      assert_kind_of String, record[:key]
      assert_kind_of Regexp, record[:pattern]
    end
  end

  test "#monitored_ip? and #matching_monitored_ip_lists reflect monitored IP lists" do
    @firewall.update_ip_lists_from_json({
      "monitoredIPAddresses" => [
        {"key" => "key1", "source" => "source1", "description" => "description1", "ips" => ["1.4.9.0/24"]}
      ]
    })

    assert @firewall.monitored_ip?("1.4.9.1")
    refute @firewall.monitored_ip?("8.8.8.8")

    matches = @firewall.matching_monitored_ip_lists("1.4.9.1")
    assert_equal 1, matches.size
    assert_equal "key1", matches.first.key
  end

  test "#user_agent_keys returns an empty array when the user agent is nil" do
    assert_equal [], @firewall.user_agent_keys(nil)
  end

  test "#reload_ip_lists never writes to disk" do
    data = {
      "blockedUserAgents" => "AdsBot-Google",
      "userAgentDetails" => [{"key" => "adsbot_google", "pattern" => "AdsBot-Google"}],
      "blockedIPAddresses" => [
        {"key" => "key1", "source" => "source1", "description" => "description1", "ips" => ["1.4.9.0/24"]}
      ]
    }

    @firewall.update_user_agents_from_json(data)
    @firewall.reload_ip_lists

    assert_kind_of Regexp, @firewall.blocked_user_agent_regexp
    assert_equal [{key: "adsbot_google", pattern: /AdsBot-Google/i}], @firewall.user_agent_details

    refute File.exist?(File.join(@ip_lists_directory, "blocked.ipls")),
      "expected IP lists not to be written to disk without calling #update_ip_lists_from_json"
    assert_nil @firewall.blocked_ip_lists
  end

  test "#reload_ip_lists picks up IP lists another instance already wrote to disk" do
    @firewall.update_ip_lists_from_json({
      "blockedIPAddresses" => [
        {"key" => "key1", "source" => "source1", "description" => "description1", "ips" => ["1.4.9.0/24"]}
      ]
    })

    other_firewall = Aikido::Zen::Firewall.new
    other_firewall.update_user_agents_from_json({"blockedUserAgents" => "AdsBot-Google"})
    other_firewall.reload_ip_lists

    assert_kind_of Aikido::Zen::Firewall::IPLists, other_firewall.blocked_ip_lists
    assert other_firewall.blocked_ip?("1.4.9.1")
  end

  test "#reload_ip_lists keeps the previous IPLists when the file on disk goes missing" do
    @firewall.update_ip_lists_from_json({
      "blockedIPAddresses" => [
        {"key" => "key1", "source" => "source1", "description" => "description1", "ips" => ["1.4.9.0/24"]}
      ]
    })
    previous = @firewall.blocked_ip_lists

    File.delete(File.join(@ip_lists_directory, "blocked.ipls"))
    @firewall.reload_ip_lists

    assert_same previous, @firewall.blocked_ip_lists
  end

  test "#reload_ip_lists closes the previous IPLists and returns a fresh one reflecting what is now on disk" do
    @firewall.update_ip_lists_from_json({
      "blockedIPAddresses" => [
        {"key" => "key1", "source" => "source1", "description" => "description1", "ips" => ["1.4.9.0/24"]}
      ]
    })
    previous = @firewall.blocked_ip_lists

    @firewall.update_ip_lists_from_json({
      "blockedIPAddresses" => [
        {"key" => "key2", "source" => "source2", "description" => "description2", "ips" => ["5.6.7.8"]}
      ]
    })

    refute_same previous, @firewall.blocked_ip_lists
    assert @firewall.blocked_ip?("5.6.7.8")
    refute @firewall.blocked_ip?("1.4.9.1")
  end
end
