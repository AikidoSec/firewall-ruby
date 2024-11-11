# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::EventTest < ActiveSupport::TestCase
  test "it exposes its type and time" do
    event = Aikido::Zen::Event.new(type: "test", time: Time.at(1234567890))

    assert_equal "test", event.type
    assert_equal Time.at(1234567890), event.time
  end

  test "#time defaults to the current time if not given" do
    freeze_time do
      event = Aikido::Zen::Event.new(type: "test")
      assert_equal Time.now.utc, event.time
    end
  end

  test "it captures the system information" do
    event = Aikido::Zen::Event.new(type: "test")

    assert_kind_of Aikido::Zen::SystemInfo, event.system_info
    assert_equal "firewall-ruby", event.system_info.library_name
  end

  test "#as_json includes the type" do
    event = Aikido::Zen::Event.new(type: "test")

    assert_equal "test", event.as_json[:type]
  end

  test "#as_json serializes the time in milliseconds" do
    event = Aikido::Zen::Event.new(type: "test", time: Time.at(123))

    assert_equal 123000, event.as_json[:time]
  end

  test "#as_json serializes the system info" do
    event = Aikido::Zen::Event.new(type: "test")
    system_info = Aikido::Zen::SystemInfo.new

    refute_nil system_info.as_json, event.as_json[:agent]
  end

  class StartedTest < ActiveSupport::TestCase
    test "sets type to started" do
      event = Aikido::Zen::Events::Started.new

      assert_equal "started", event.type
    end

    test "allows overriding time" do
      event = Aikido::Zen::Events::Started.new(time: Time.at(1234567890))

      assert_equal Time.at(1234567890), event.time
    end
  end

  class AttackTest < ActiveSupport::TestCase
    test "sets type to detected_attack" do
      attack = TestAttack.new
      event = Aikido::Zen::Events::Attack.new(attack: attack)

      assert_equal "detected_attack", event.type
    end

    test "includes the attack's JSON representation" do
      attack = TestAttack.new(context: stub_context)
      event = Aikido::Zen::Events::Attack.new(attack: attack)

      assert_equal({some: "info"}, event.as_json[:attack])
    end

    test "includes the request's JSON representation" do
      context = stub_context

      attack = TestAttack.new(context: context)
      event = Aikido::Zen::Events::Attack.new(attack: attack)

      assert_equal context.request.as_json, event.as_json[:request]
    end

    def stub_context(**options)
      env = Rack::MockRequest.env_for("/test", **options)
      Aikido::Zen::Context.from_rack_env(env)
    end

    class TestAttack < Aikido::Zen::Attack
      def initialize(sink: nil, context: nil, operation: "test")
        super
      end

      def log_message
        "test attack"
      end

      def as_json
        {some: "info"}
      end

      def exception(*)
        Aikido::Zen::UnderAttackError.new(self)
      end
    end
  end

  class HeartbeatTest < ActiveSupport::TestCase
    setup do
      @stats = Aikido::Zen::Collector::Stats.new
      @stats.start(Time.at(1234567890))
      @stats.flush(at: Time.at(1234577890))

      @users = Aikido::Zen::Collector::Users.new
      @hosts = Aikido::Zen::Collector::Hosts.new
      @routes = Aikido::Zen::Collector::Routes.new
    end

    test "sets type to heartbeat" do
      event = Aikido::Zen::Events::Heartbeat.new(
        stats: @stats, users: @users, hosts: @hosts, routes: @routes
      )

      assert_equal "heartbeat", event.type
    end

    test "includes the basic structure with timestamps if no data has been collected" do
      event = Aikido::Zen::Events::Heartbeat.new(
        stats: @stats, users: @users, hosts: @hosts, routes: @routes
      )

      assert_hash_subset_of event.as_json, {
        stats: {
          startedAt: 1234567890000,
          endedAt: 1234577890000,
          sinks: {},
          requests: {
            total: 0,
            aborted: 0,
            attacksDetected: {total: 0, blocked: 0}
          }
        },
        users: [],
        routes: [],
        hostnames: []
      }
    end

    test "it includes the API spec with the routes" do
      @routes.add(build_request_for("/", stub_route("GET", "/")))

      @routes.add(build_request_for("/users", stub_route("POST", "/users(.:format)"), {
        :method => "POST",
        :input => "user[name]=Alice&user[email]=alice@example.com",
        "CONTENT_TYPE" => "multipart/form-data"
      }))

      @routes.add(build_request_for("/users", stub_route("POST", "/users(.:format)"), {
        :method => "POST",
        :input => %({"user":{"name":"Alice","email":"alice@example.com","age":35}}),
        "CONTENT_TYPE" => "application/json"
      }))

      @routes.add(
        build_request_for("/users?search=alice&page=2", stub_route("GET", "/users(.:format)"))
      )

      event = Aikido::Zen::Events::Heartbeat.new(
        stats: @stats, users: @users, hosts: @hosts, routes: @routes
      )
      serialized = event.as_json

      assert_includes serialized[:routes],
        {path: "/", method: "GET", hits: 1, apispec: {}}
      assert_includes serialized[:routes],
        {
          path: "/users(.:format)",
          method: "GET",
          hits: 1,
          apispec: {
            query: {
              "type" => "object",
              "properties" => {
                "search" => {"type" => "string"},
                "page" => {"type" => "string"}
              }
            }
          }
        }
      assert_includes serialized[:routes],
        {
          path: "/users(.:format)",
          method: "POST",
          hits: 2,
          apispec: {
            body: {
              type: :json,
              schema: {
                "type" => "object",
                "properties" => {
                  "user" => {
                    "type" => "object",
                    "properties" => {
                      "name" => {"type" => "string"},
                      "email" => {"type" => "string"},
                      "age" => {"type" => "integer", "optional" => true}
                    }
                  }
                }
              }
            }
          }
        }
    end

    def stub_outbound(host, port)
      Aikido::Zen::OutboundConnection.new(host: host, port: port)
    end

    def stub_route(verb, path)
      Aikido::Zen::Route.new(path: path, verb: verb)
    end

    def stub_request(route:, schema: nil)
      StubRequest.new(route, schema)
    end

    def build_request_for(path, route, env = {})
      env = Rack::MockRequest.env_for(path, env)
      env = Rails.application.env_config.merge(env)

      Aikido::Zen.current_context = Aikido::Zen::Context::RAILS_REQUEST_BUILDER.call(env)
      Aikido::Zen.current_context.request.tap do |req|
        req.singleton_class.define_method(:route) { route }
      end
    end

    StubRequest = Struct.new(:route, :schema)
  end
end
