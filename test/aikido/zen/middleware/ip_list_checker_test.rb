# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::IPListCheckerTest < ActiveSupport::TestCase
  module Configuration
    def configure_ips(ip_list_name, ips, key: "key", source: "source", description: "description")
      if ips.empty?
        @settings.update_from_runtime_firewall_lists_json({
          ip_list_name => []
        })
      else
        @settings.update_from_runtime_firewall_lists_json({
          ip_list_name => [
            {
              "key" => key,
              "source" => source,
              "description" => description,
              "ips" => ips
            }
          ]
        })
      end
    end

    def configure_blocked_ips(*args, **kwargs)
      configure_ips("blockedIPAddresses", *args, **kwargs)
    end

    def configure_allowed_ips(*args, **kwargs)
      configure_ips("allowedIPAddresses", *args, **kwargs)
    end

    def configure_monitored_ips(*args, **kwargs)
      configure_ips("monitoredIPAddresses", *args, **kwargs)
    end

    DEFAULT_BLOCKED_IPS = [
      "1.4.9.0/24",
      "1.173.94.92/30",
      "2.16.20.0/23",
      "2.16.53.0/24",
      "2.16.103.0/24",
      "2.16.154.0/24",
      "2.17.144.0/23",
      "2.17.146.0/24",
      "2.19.181.0/24",
      "2.19.204.0/23",
      "2.20.254.0/23",
      "2.22.237.0/24",
      "2.23.167.0/24",
      "2.56.26.0/23",
      "2.56.88.0/23",
      "2.56.138.0/24",
      "2.56.178.0/24",
      "2.56.180.0/22",
      "2.56.228.0/22",
      "2.56.240.0/23",
      "2.56.242.0/24",
      "2.57.0.0/24",
      "2.57.37.0/24",
      "2.57.38.0/24",
      "2.57.52.0/22",
      "2.57.80.0/22",
      "2.57.112.0/22",
      "2.57.184.0/22",
      "2.58.68.0/22",
      "2.58.96.0/23",
      "2.58.98.0/24",
      "2.58.124.0/22",
      "2.59.40.0/22",
      "2.59.48.0/23",
      "2.59.50.0/24",
      "2.59.51.0/24",
      "2.59.76.0/22",
      "2.59.80.0/22",
      "2.59.160.0/23",
      "2.59.176.0/22",
      "2.59.213.0/24",
      "2.59.214.0/23",
      "2.59.216.0/22",
      "2.59.240.0/22",
      "2.60.0.0/15",
      "2.62.0.0/16",
      "2.63.0.0/17",
      "2.63.128.0/20",
      "2.63.160.0/20",
      "2.63.192.0/19",
      "2.63.240.0/20",
      "2.92.0.0/14",
      "5.1.41.0/24",
      "5.1.47.0/24",
      "5.1.48.0/21",
      "5.2.32.0/19",
      "5.3.0.0/16",
      "5.8.8.0/21",
      "5.8.16.0/23",
      "5.8.19.0/24"
    ]

    # The same list of IPs is used for either blocking or allowing.
    DEFAULT_ALLOWED_IPS = DEFAULT_BLOCKED_IPS

    # The same list of IPs is used.
    DEFAULT_MONITORED_IPS = DEFAULT_BLOCKED_IPS
  end

  class ConfigurationTest < ActiveSupport::TestCase
    include Configuration
    extend ActiveSupport::Testing::Declarative

    setup do
      @settings = Aikido::Zen.runtime_settings
    end

    test "blocked IP lists are configured and reconfigured" do
      assert @settings.blocked_ip_lists.empty?

      configure_blocked_ips(DEFAULT_BLOCKED_IPS)

      refute @settings.blocked_ip_lists.empty?

      ["2.16.53.5", "2.16.53.6"].each do |ip|
        assert(@settings.blocked_ip?(ip))
      end

      configure_blocked_ips([])

      assert @settings.blocked_ip_lists.empty?

      ["2.16.53.5", "2.16.53.6"].each do |ip|
        refute(@settings.blocked_ip?(ip))
      end
    end

    test "allowed IP lists are configured and reconfigured" do
      assert @settings.allowed_ip_lists.empty?

      configure_allowed_ips(DEFAULT_ALLOWED_IPS)

      refute @settings.allowed_ip_lists.empty?

      ["2.16.53.5", "2.16.53.6"].each do |ip|
        assert(@settings.allowed_ip?(ip))
      end

      configure_allowed_ips([])

      assert @settings.allowed_ip_lists.empty?

      ["2.16.53.5", "2.16.53.6"].each do |ip|
        assert(@settings.allowed_ip?(ip))
      end
    end

    test "monitored IP lists are configured and reconfigured" do
      assert @settings.monitored_ip_lists.empty?

      configure_monitored_ips(DEFAULT_MONITORED_IPS)

      refute @settings.monitored_ip_lists.empty?

      ["2.16.53.5", "2.16.53.6"].each do |ip|
        assert(@settings.monitored_ip?(ip))
      end

      configure_monitored_ips([])

      assert @settings.monitored_ip_lists.empty?

      ["2.16.53.5", "2.16.53.6"].each do |ip|
        refute(@settings.monitored_ip?(ip))
      end
    end
  end

  module GenericRequestTests
    include Configuration
    extend ActiveSupport::Testing::Declarative

    test "requests are allowed if all blocked IP lists are empty" do
      env = env_for("/", {"HTTP_X_FORWARDED_FOR" => "2.16.53.5"})

      status, = @middleware.call(env)

      assert_equal 200, status

      assert_equal 0, Aikido::Zen.collector.stats.ip_lists.length
    end

    test "requests are allowed if all allowed IP lists are empty" do
      env = env_for("/", {"HTTP_X_FORWARDED_FOR" => "2.16.53.5"})

      status, = @middleware.call(env)

      assert_equal 200, status

      assert_equal 0, Aikido::Zen.collector.stats.ip_lists.length
    end

    test "requests are blocked if the blocked IP lists are not empty and the client IP is in any blocked IP list" do
      configure_blocked_ips(DEFAULT_BLOCKED_IPS, description: "reason")

      3.times do
        env = env_for("/", {"HTTP_X_FORWARDED_FOR" => "2.16.53.5"})

        status, _, body = @middleware.call(env)

        assert_equal 403, status
        assert_equal ["Your IP is blocked due to reason."], body
      end

      assert_equal 1, Aikido::Zen.collector.stats.ip_lists.length
      assert_equal 3, Aikido::Zen.collector.stats.ip_lists["key"]
    end

    test "requests are allowed if the allowed IP lists are not empty and the client IP is in any allowed IP list" do
      configure_allowed_ips(DEFAULT_ALLOWED_IPS)

      env = env_for("/", {"HTTP_X_FORWARDED_FOR" => "2.16.53.5"})

      status, = @middleware.call(env)

      assert_equal 200, status

      assert_equal 0, Aikido::Zen.collector.stats.ip_lists.length
    end

    test "requests are blocked if the allowed IP lists are not empty and the client IP is not in any allowed IP list" do
      configure_allowed_ips(DEFAULT_ALLOWED_IPS)

      env = env_for("/", {"HTTP_X_FORWARDED_FOR" => "4.3.2.1"})

      status, _, body = @middleware.call(env)

      assert_equal 403, status
      assert_equal ["Your IP address is not allowed to access this resource. (Your IP: 4.3.2.1)"], body

      assert_equal 0, Aikido::Zen.collector.stats.ip_lists.length
    end

    test "requests are allowed and monitored if the monitored IP lists are not empty and the client IP is in any monitored IP list" do
      configure_monitored_ips(DEFAULT_MONITORED_IPS)

      3.times do
        env = env_for("/", {"HTTP_X_FORWARDED_FOR" => "2.16.53.5"})

        status, = @middleware.call(env)

        assert_equal 200, status
      end

      assert_equal 1, Aikido::Zen.collector.stats.ip_lists.length
      assert_equal 3, Aikido::Zen.collector.stats.ip_lists["key"]
    end

    test "requests are allowed if the client IP is in the bypassed IP set" do
      @settings.bypassed_ips = Aikido::Zen::RuntimeSettings::IPSet.from_json(["2.16.53.5"])

      configure_blocked_ips(DEFAULT_BLOCKED_IPS)

      env = env_for("/", {"HTTP_X_FORWARDED_FOR" => "2.16.53.5"})

      status, = @middleware.call(env)

      assert_equal 200, status

      assert_equal 0, Aikido::Zen.collector.stats.ip_lists.length
    end

    test "complete example with blocked and monitored IP lists" do
      blocked_ip_lists = [
        {
          "key" => "key1",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_BLOCKED_IPS.filter { |ip| ip.start_with?("1") }
        },
        {
          "key" => "key2",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_BLOCKED_IPS.filter { |ip| ip.start_with?("2.16.") }
        },
        {
          "key" => "key3",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_BLOCKED_IPS.filter { |ip| ip.start_with?("2.17.") }
        },
        {
          "key" => "key4",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_BLOCKED_IPS.filter { |ip| ip.start_with?("2.19.") }
        },
        {
          "key" => "key5",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_BLOCKED_IPS.filter { |ip| ip.start_with?("5.1") }
        },
        {
          "key" => "key6",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_BLOCKED_IPS.filter { |ip| ip.start_with?("5.2") }
        }
      ]

      monitored_ip_lists = [
        {
          "key" => "key7",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_MONITORED_IPS.filter { |ip| ip.start_with?("5.8") }
        },
        {
          "key" => "key8",
          "source" => "source",
          "description" => "reason",
          "ips" => DEFAULT_MONITORED_IPS.filter { |ip| ip.start_with?("5.3") }
        }
      ]

      @settings.update_from_runtime_firewall_lists_json({
        "blockedIPAddresses" => blocked_ip_lists,
        "monitoredIPAddresses" => monitored_ip_lists
      })

      blocked_ips = [
        "1.4.9.3",
        "2.16.53.5",
        "1.4.9.7",
        "2.16.53.5",
        "2.16.53.6"
      ]

      blocked_ips.each do |blocked_ip|
        env = env_for("/", {"HTTP_X_FORWARDED_FOR" => blocked_ip})

        status, _, body = @middleware.call(env)

        assert_equal 403, status
        assert_equal ["Your IP is blocked due to reason."], body
      end

      monitored_ips = [
        "5.8.16.1",
        "5.8.16.3",
        "5.3.0.1",
        "5.3.1.1",
        "5.3.2.1",
        "5.3.4.100",
        "5.3.4.200",
        "5.8.16.5"
      ]

      monitored_ips.each do |monitored_ip|
        env = env_for("/", {"HTTP_X_FORWARDED_FOR" => monitored_ip})

        status, = @middleware.call(env)

        assert_equal 200, status
      end

      assert_equal 4, Aikido::Zen.collector.stats.ip_lists.length
      assert_equal 2, Aikido::Zen.collector.stats.ip_lists["key1"]
      assert_equal 3, Aikido::Zen.collector.stats.ip_lists["key2"]
      assert_equal 3, Aikido::Zen.collector.stats.ip_lists["key7"]
      assert_equal 5, Aikido::Zen.collector.stats.ip_lists["key8"]
    end
  end

  class RackRequestTest < ActiveSupport::TestCase
    include GenericRequestTests

    def env_for(path, env = {})
      Rack::MockRequest.env_for(path, env)
    end

    setup do
      Aikido::Zen.config.request_builder = Aikido::Zen::Context::RACK_REQUEST_BUILDER

      @settings = Aikido::Zen.runtime_settings

      app = ->(_env) { [200, {}, ["OK"]] }
      @middleware = Aikido::Zen::Middleware::IPListChecker.new(app)
    end
  end

  class RailsRequestTest < ActiveSupport::TestCase
    include GenericRequestTests

    def env_for(path, env = {})
      env = Rack::MockRequest.env_for(path, env)
      Rails.application.env_config.merge(env)
    end

    setup do
      Aikido::Zen.config.request_builder = Aikido::Zen::Context::RAILS_REQUEST_BUILDER

      @settings = Aikido::Zen.runtime_settings

      app = ->(_env) { [200, {}, ["OK"]] }
      @middleware = Aikido::Zen::Middleware::IPListChecker.new(app)
    end
  end
end
