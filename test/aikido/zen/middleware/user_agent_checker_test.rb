# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::UserAgentCheckerTest < ActiveSupport::TestCase
  module GenericTests
    extend ActiveSupport::Testing::Declarative

    def update_runtime_firewall_lists
      @settings.update_from_runtime_firewall_lists_json({
        "blockedUserAgents" => "Applebot-Extended|CCBot|ClaudeBot|Google-Extended|GPTBot|meta-externalagent|anthropic-ai|AdsBot-Google|Mediapartners-Google|Mediapartners \\(Googlebot\\)|Google-Adwords",
        "monitoredUserAgents" => "ChatGPT-User|Meta-ExternalFetcher|Claude-Web|GitHubCopilotChat|Claude-User",
        "userAgentDetails" => [
          {"key" => "applebot_extended", "pattern" => "Applebot-Extended"},
          {"key" => "ccbot", "pattern" => "CCBot"},
          {"key" => "claudebot", "pattern" => "ClaudeBot"},
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
    end

    test "requests without user agent are not tracked" do
      update_runtime_firewall_lists

      env = env_for("/")

      3.times do
        assert_equal [200, {}, ["OK"]], @middleware.call(env)
      end

      assert_equal 0, Aikido::Zen.collector.stats.user_agents.length
    end

    test "requests from non-blocked and non-monitored user agents are not blocked or tracked" do
      user_agent = "AdsBot-Google"

      env = env_for("/", {"HTTP_USER_AGENT" => user_agent})

      3.times do
        assert_equal [200, {}, ["OK"]], @middleware.call(env)
      end

      assert_equal 0, Aikido::Zen.collector.stats.user_agents.length
    end

    test "requests from blocked user agents are tracked" do
      update_runtime_firewall_lists

      user_agent = "AdsBot-Google"
      user_agent_keys = ["adsbot_google"]

      env = env_for("/", {"HTTP_USER_AGENT" => user_agent})

      message = "You are not allowed to access this resource because you have been identified as a bot."

      3.times do
        assert_equal [403, {"Content-Type" => "text/plain"}, [message]], @middleware.call(env)
      end

      assert_equal 1, Aikido::Zen.collector.stats.user_agents.length

      user_agent_keys.each do |user_agent_key|
        assert_equal 3, Aikido::Zen.collector.stats.user_agents[user_agent_key]
      end
    end

    test "requests from monitored user agents are tracked" do
      update_runtime_firewall_lists

      user_agent = "GitHubCopilotChat"
      user_agent_keys = ["githubcopilotchat"]

      env = env_for("/", {"HTTP_USER_AGENT" => user_agent})

      3.times do
        assert_equal [200, {}, ["OK"]], @middleware.call(env)
      end

      assert_equal 1, Aikido::Zen.collector.stats.user_agents.length

      user_agent_keys.each do |user_agent_key|
        assert_equal 3, Aikido::Zen.collector.stats.user_agents[user_agent_key]
      end
    end
  end

  class RackRequestTest < ActiveSupport::TestCase
    include GenericTests

    def env_for(path, env = {})
      Rack::MockRequest.env_for(path, env)
    end

    setup do
      Aikido::Zen.config.request_builder = Aikido::Zen::Context::RACK_REQUEST_BUILDER

      @config = Aikido::Zen.config
      @settings = Aikido::Zen.runtime_settings

      app = ->(env) { [200, {}, ["OK"]] }
      @middleware = Aikido::Zen::Middleware::UserAgentChecker.new(app)
    end
  end

  class RailsRequestTest < ActiveSupport::TestCase
    include GenericTests

    def env_for(path, env = {})
      env = Rack::MockRequest.env_for(path, env)
      Rails.application.env_config.merge(env)
    end

    setup do
      Aikido::Zen.config.request_builder = Aikido::Zen::Context::RAILS_REQUEST_BUILDER

      @config = Aikido::Zen.config
      @settings = Aikido::Zen.runtime_settings

      app = ->(env) { [200, {}, ["OK"]] }
      @middleware = Aikido::Zen::Middleware::UserAgentChecker.new(app)
    end
  end
end
