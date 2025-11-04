# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RequestTest < ActiveSupport::TestCase
  # Run the exact same test cases against multiple Request implementations
  # (see below)
  module Tests
    extend ActiveSupport::Testing::Declarative

    test "#normalized_headers returns an empty Hash for an empty env" do
      req = build_request({})
      assert_empty req.normalized_headers
    end

    test "#normalized_headers maps Content-Type and Content-Length correctly" do
      env = Rack::MockRequest.env_for("/test", {
        :method => "POST",
        :input => "request_body",
        "CONTENT_TYPE" => "application/json"
      })
      req = build_request(env)

      assert_equal "12", req.normalized_headers["Content-Length"]
      assert_equal "application/json", req.normalized_headers["Content-Type"]
    end

    test "#normalized_headers maps CGI-style headers to pretty names" do
      env = Rack::MockRequest.env_for("/test", {
        :method => "POST",
        :input => "request_body",
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json",
        "HTTP_USER_AGENT" => "test_suite",
        "HTTP_X_FORWARDED_FOR" => "1.2.3.4"
      })
      req = build_request(env)

      assert_equal "application/json", req.normalized_headers["Accept"]
      assert_equal "1.2.3.4", req.normalized_headers["X-Forwarded-For"]
      assert_equal "test_suite", req.normalized_headers["User-Agent"]
    end

    test "#as_json includes the request method and URL" do
      env = Rack::MockRequest.env_for("/test", {
        :method => "POST",
        :input => "request_body",
        "CONTENT_TYPE" => "application/json"
      })
      req = build_request(env)

      assert_equal(
        {method: "post", url: "http://example.org/test"},
        req.as_json.slice(:method, :url)
      )
    end

    test "#as_json includes the remote IP" do
      env = Rack::MockRequest.env_for("/test", "REMOTE_ADDR" => "1.2.3.4")
      req = build_request(env)

      assert_equal "1.2.3.4", req.as_json[:ipAddress]
    end

    test "#as_json includes the remote IP from the custom client IP header" do
      Aikido::Zen.config.client_ip_header = "HTTP_CUSTOM_CLIENT_IP"

      env = Rack::MockRequest.env_for("/test", "REMOTE_ADDR" => "1.2.3.4", "HTTP_CUSTOM_CLIENT_IP" => "4.3.2.1")
      req = build_request(env)

      assert_equal "4.3.2.1", req.as_json[:ipAddress]

      Aikido::Zen.config.client_ip_header = nil
    end

    test "#as_json includes the User-Agent" do
      env = Rack::MockRequest.env_for("/test", "HTTP_USER_AGENT" => "Some/UA")
      req = build_request(env)

      assert_equal "Some/UA", req.as_json[:userAgent]
    end

    test "#as_json includes the framework handling the request as source" do
      env = Rack::MockRequest.env_for("/test")
      req = build_request(env)

      assert_equal req.framework, req.as_json[:source]
    end

    test "#schema builds the request schema" do
      env = Rack::MockRequest.env_for("/test")
      req = build_request(env)

      assert_kind_of Aikido::Zen::Request::Schema, req.schema
    end
  end

  class RackRequestTest < ActiveSupport::TestCase
    include Tests

    test "sets the framework to 'rack'" do
      request = build_request({})
      assert_equal "rack", request.framework
    end

    test "#as_json includes the paremeterized route being requested" do
      env = Rack::MockRequest.env_for("/test/123")
      req = build_request(env)

      assert_equal "/test/:number", req.as_json[:route]
    end

    def build_request(env)
      Aikido::Zen.current_context = Aikido::Zen::Context::RACK_REQUEST_BUILDER.call(env)
      Aikido::Zen.current_context.request
    end
  end

  class ActionDispatchRequestTest < ActiveSupport::TestCase
    include Tests

    test "sets the framework to 'rails'" do
      request = build_request({})
      assert_equal "rails", request.framework
    end

    test "#as_json includes the parameterized route being requested" do
      Rails.application.routes.draw do
        get "/cats/:id", to: "cats#show", as: :cat
      end

      env = Rack::MockRequest.env_for("/cats/123")
      req = build_request(env)

      assert_equal "/cats/:id(.:format)", req.as_json[:route]
    end

    test "#schema gets built from the request body" do
      env = Rack::MockRequest.env_for("/users?test=true", {
        "CONTENT_TYPE" => "application/json",
        :method => "POST",
        :input => %(
          {
            "user": {
              "email": "alice@example.com",
              "name": "Alice",
              "accepts_terms": true,
              "age": 35,
              "interests": ["foo", "bar", "baz"]
            }
          }
        )
      })
      req = build_request(env)

      assert_equal req.schema.as_json, {
        body: {
          type: :json,
          schema: {
            "type" => "object",
            "properties" => {
              "user" => {
                "type" => "object",
                "properties" => {
                  "email" => {"type" => "string"},
                  "name" => {"type" => "string"},
                  "accepts_terms" => {"type" => "boolean"},
                  "age" => {"type" => "number"},
                  "interests" => {
                    "type" => "array",
                    "items" => {"type" => "string"}
                  }
                }
              }
            }
          }
        },
        query: {
          "type" => "object",
          "properties" => {
            "test" => {"type" => "string"}
          }
        }
      }
    end

    def build_request(env)
      env = Rails.application.env_config.merge(env)
      Aikido::Zen.current_context = Aikido::Zen::Context::RAILS_REQUEST_BUILDER.call(env)
      Aikido::Zen.current_context.request
    end
  end
end
