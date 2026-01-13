# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::AttackProtectorTest < ActiveSupport::TestCase
  module GenericTests
    extend ActiveSupport::Testing::Declarative

    def build_context_for(path, env = {})
      env = env_for(path, env)
      Aikido::Zen::Context.from_rack_env(env)
    end

    def assert_mock_middleware(context)
      app = Minitest::Mock.new
      zen = Minitest::Mock.new

      zen.expect :runtime_settings, @settings
      middleware = Aikido::Zen::Middleware::AttackProtector.new(app, zen: zen)
      assert_mock zen
      assert_mock app

      zen.expect :current_context, context
      app.expect(:call, [200, {}, ["OK"]]) { |arg| arg.is_a?(Hash) }
      middleware.call({})
      assert_mock zen
      assert_mock app
    end

    test "protection is enabled by default" do
      context = build_context_for("/path", "REMOTE_ADDR" => "1.2.3.4")

      assert_mock_middleware(context)
      refute context.protection_disabled?
    end

    test "protection is disabled when the request IP is an allowed IP" do
      @settings.update_from_runtime_config_json({
        "allowedIPAddresses" => ["10.0.0.1"]
      })

      unprotected_ctx = build_context_for("/path", "REMOTE_ADDR" => "10.0.0.1")
      assert_mock_middleware(unprotected_ctx)
      assert unprotected_ctx.protection_disabled?

      protected_ctx = build_context_for("/path", "REMOTE_ADDR" => "1.2.3.4")
      assert_mock_middleware(protected_ctx)
      refute protected_ctx.protection_disabled?
    end
  end

  class RackRequestTest < ActiveSupport::TestCase
    include GenericTests

    setup do
      Aikido::Zen.config.request_builder = Aikido::Zen::Context::RACK_REQUEST_BUILDER

      @settings = Aikido::Zen.runtime_settings
    end

    def env_for(path, env = {})
      Rack::MockRequest.env_for(path, env)
    end

    test "the runtime settings endpoints are checked" do
      @settings.update_from_runtime_config_json({
        "success" => true,
        "serviceId" => 1234,
        "configUpdatedAt" => 1717171717000,
        "heartbeatIntervalInMS" => 60000,
        "endpoints" => [
          {
            "method" => "GET",
            "route" => "/unprotected",
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
            "route" => "/protected",
            "forceProtectionOff" => false,
            "graphql" => nil,
            "allowedIPAddresses" => [],
            "rateLimiting" => {
              "enabled" => false,
              "maxRequests" => 100,
              "windowSizeInMS" => 60000
            }
          }
        ],
        "blockedUserIds" => [],
        "allowedIPAddresses" => [],
        "receivedAnyStats" => false
      })

      unprotected_ctx = build_context_for("/unprotected", method: "GET")
      assert_mock_middleware(unprotected_ctx)
      assert unprotected_ctx.protection_disabled?

      protected_ctx = build_context_for("/protected", method: "GET")
      assert_mock_middleware(protected_ctx)
      refute protected_ctx.protection_disabled?

      default_ctx = build_context_for("/not_configured", method: "GET")
      assert_mock_middleware(default_ctx)
      refute default_ctx.protection_disabled?
    end

    test "all the runtime settings endpoints are checked" do
      @settings.update_from_runtime_config_json({
        "success" => true,
        "serviceId" => 1234,
        "configUpdatedAt" => 1717171717000,
        "heartbeatIntervalInMS" => 60000,
        "endpoints" => [
          {
            "method" => "GET",
            "route" => "/unprotected",
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
            "route" => "/protected",
            "forceProtectionOff" => false,
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
            "route" => "/protect*",
            "forceProtectionOff" => false,
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
            "route" => "/*protected",
            "forceProtectionOff" => true,
            "graphql" => nil,
            "allowedIPAddresses" => [],
            "rateLimiting" => {
              "enabled" => false,
              "maxRequests" => 100,
              "windowSizeInMS" => 60000
            }
          }
        ],
        "blockedUserIds" => [],
        "allowedIPAddresses" => [],
        "receivedAnyStats" => false
      })

      unprotected_ctx = build_context_for("/unprotected", method: "GET")
      assert_mock_middleware(unprotected_ctx)
      assert unprotected_ctx.protection_disabled?

      protected_ctx = build_context_for("/protected", method: "GET")
      assert_mock_middleware(protected_ctx)
      assert protected_ctx.protection_disabled?

      default_ctx = build_context_for("/not_configured", method: "GET")
      assert_mock_middleware(default_ctx)
      refute default_ctx.protection_disabled?
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

      @settings = Aikido::Zen.runtime_settings
    end

    test "the runtime settings endpoints are checked" do
      Rails.application.routes.draw do
        get "/protected" => "example#protected"
        get "/unprotected" => "example#unprotected"
        get "/not_configured" => "example#not_configured"
      end

      @settings.update_from_runtime_config_json({
        "endpoints" => [
          {
            "method" => "GET",
            "route" => "/unprotected(.:format)",
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
            "route" => "/protected(.:format)",
            "forceProtectionOff" => false,
            "graphql" => nil,
            "allowedIPAddresses" => [],
            "rateLimiting" => {
              "enabled" => false,
              "maxRequests" => 100,
              "windowSizeInMS" => 60000
            }
          }
        ]
      })

      unprotected_ctx = build_context_for("/unprotected", method: "GET")
      assert_mock_middleware(unprotected_ctx)
      assert unprotected_ctx.protection_disabled?

      protected_ctx = build_context_for("/protected", method: "GET")
      assert_mock_middleware(protected_ctx)
      refute protected_ctx.protection_disabled?

      default_ctx = build_context_for("/not_configured", method: "GET")
      assert_mock_middleware(default_ctx)
      refute default_ctx.protection_disabled?
    end

    test "all the runtime settings endpoints are checked" do
      Rails.application.routes.draw do
        get "/protected" => "example#protected"
        get "/unprotected" => "example#unprotected"
        get "/not_configured" => "example#not_configured"
      end

      @settings.update_from_runtime_config_json({
        "endpoints" => [
          {
            "method" => "GET",
            "route" => "/unprotected(.:format)",
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
            "route" => "/protected(.:format)",
            "forceProtectionOff" => false,
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
            "route" => "/protect*(.:format)",
            "forceProtectionOff" => false,
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
            "route" => "/*protected(.:format)",
            "forceProtectionOff" => true,
            "graphql" => nil,
            "allowedIPAddresses" => [],
            "rateLimiting" => {
              "enabled" => false,
              "maxRequests" => 100,
              "windowSizeInMS" => 60000
            }
          }
        ]
      })

      unprotected_ctx = build_context_for("/unprotected", method: "GET")
      assert_mock_middleware(unprotected_ctx)
      assert unprotected_ctx.protection_disabled?

      protected_ctx = build_context_for("/protected", method: "GET")
      assert_mock_middleware(protected_ctx)
      assert protected_ctx.protection_disabled?

      default_ctx = build_context_for("/not_configured", method: "GET")
      assert_mock_middleware(default_ctx)
      refute default_ctx.protection_disabled?
    end
  end
end
