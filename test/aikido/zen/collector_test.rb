# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::CollectorTest < ActiveSupport::TestCase
  include StubsCurrentContext

  setup do
    @config = Aikido::Zen.config
    @collector = Aikido::Zen::Collector.new(config: @config)
    @sink = stub_sink(name: "test")
  end

  test "#start sets the time for the current stats period" do
    assert_changes "@collector.stats.started_at", from: nil, to: Time.at(123456789) do
      @collector.start(at: Time.at(123456789))
    end
  end

  test "#track_request increments the number of requests" do
    assert_difference "@collector.stats.requests", +2 do
      @collector.track_request(stub_request)
      @collector.track_request(stub_request)
    end
  end

  test "#track_request tracks how many times the given route was visited" do
    request_1 = stub_request("/get")
    route_1 = stub_route("GET", "/get")

    request_2 = stub_request("/post", "REQUEST_METHOD" => "POST")
    route_2 = stub_route("POST", "/post")

    assert_difference -> { @collector.routes[route_1].hits }, +2 do
      assert_difference -> { @collector.routes[route_2].hits }, +1 do
        @collector.track_request(request_1)
        @collector.track_request(request_2)
        @collector.track_request(request_1)
      end
    end
  end

  test "#track_request stores the request schema" do
    request = stub_request("/get?q=test")

    @collector.track_request(request)

    schema = @collector.routes[stub_route("GET", "/get")].schema
    assert_equal schema.as_json, {
      query: {"type" => "object", "properties" => {"q" => {"type" => "string"}}}
    }
  end

  test "#track_scan increments the number of scans for the sink" do
    assert_difference "@collector.stats.sinks[@sink.name].scans", +2 do
      @collector.track_scan(stub_scan(sink: @sink))
      @collector.track_scan(stub_scan(sink: @sink))
    end
  end

  test "#track_attack increments the number of attacks detected for the sink" do
    assert_difference "@collector.stats.sinks[@sink.name].attacks", +2 do
      @collector.track_attack(stub_attack(sink: @sink))
      @collector.track_attack(stub_attack(sink: @sink))
    end
  end

  test "#track_outbound tracks which connections have been made" do
    c1 = stub_outbound(host: "example.com", port: 80)
    c2 = stub_outbound(host: "example.com", port: 443)

    assert_difference "@collector.hosts.size", +2 do
      @collector.track_outbound(c1)
      @collector.track_outbound(c2)
    end

    assert_includes @collector.hosts, c1
    assert_includes @collector.hosts, c2
  end

  test "#add_outbound doesn't count the same host/port pair more than once" do
    conn = stub_outbound(host: "example.com", port: 443)

    assert_difference "@collector.hosts.size", +1 do
      @collector.track_outbound(conn)
      @collector.track_outbound(conn)
    end

    assert_includes @collector.hosts, conn
  end

  test "#add_outbound limits the amount of connections tracked" do
    conn = stub_outbound(host: "example.com", port: 0)
    @collector.track_outbound(conn)

    assert_includes @collector.hosts, conn

    @config.max_outbound_connections.times do |idx|
      @collector.track_outbound(stub_outbound(host: "test.com", port: idx))
    end

    assert_equal @config.max_outbound_connections, @collector.hosts.size
    refute_includes @collector.hosts, conn
  end

  test "#track_user tracks which users have visited the app" do
    initial_time = Time.utc(2024, 9, 1, 16, 20, 42)

    u1 = stub_actor(id: "123", name: "Alice", seen_at: initial_time, ip: "1.2.3.4")
    u2 = stub_actor(id: "345", name: "Bob", seen_at: initial_time + 5, ip: "2.3.4.5")

    assert_difference "@collector.users.size", +2 do
      @collector.track_user(u1)
      @collector.track_user(u2)
    end

    assert_includes @collector.users, u1
    assert_includes @collector.users, u2
  end

  test "#track_user doesn't count a user more than once" do
    initial_time = Time.utc(2024, 9, 1, 16, 20, 42)

    user = stub_actor(id: "123", name: "Alice", seen_at: initial_time, ip: "1.2.3.4")

    assert_difference "@collector.users.size", +1 do
      @collector.track_user(user)
      @collector.track_user(user)
    end
  end

  test "#track_user updates the user's last_seen_at when the user is added multiple times" do
    freeze_time do
      user = stub_actor(id: "123", seen_at: Time.utc(2024, 9, 1, 16, 20, 42))
      @collector.track_user(user)

      travel(20)

      assert_difference "user.last_seen_at", +20 do
        same_user_in_diff_request = stub_actor(id: user.id)
        @collector.track_user(same_user_in_diff_request)
      end
    end
  end

  test "#track_user updates the user's ip to the current context's request IP" do
    user = stub_actor(id: "123", ip: "1.2.3.4")
    @collector.track_user(user)

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "6.7.8.9")
    with_context Aikido::Zen::Context.from_rack_env(env) do
      assert_changes "user.ip", to: "6.7.8.9" do
        same_user_in_diff_request = stub_actor(id: user.id)
        @collector.track_user(same_user_in_diff_request)
      end
    end
  end

  test "#flush sets the ended_at and builds a Heartbeat event" do
    @collector.start(at: Time.at(1234567890))
    event = @collector.flush(at: Time.at(1234577890))

    assert_hash_subset_of event.as_json, {
      stats: {
        startedAt: 1234567890000,
        endedAt: 1234577890000,
        sinks: {},
        requests: {
          total: 0,
          aborted: 0,
          attacksDetected: {
            total: 0,
            blocked: 0
          }
        }
      },
      users: [],
      routes: [],
      hostnames: []
    }
  end

  test "#flush includes the request stats in the event" do
    @collector.start(at: Time.at(1234567890))
    3.times { @collector.track_request(stub_request) }
    event = @collector.flush(at: Time.at(1234577890))

    assert_hash_subset_of event.as_json, {
      stats: {
        startedAt: 1234567890000,
        endedAt: 1234577890000,
        sinks: {},
        requests: {
          total: 3,
          aborted: 0,
          attacksDetected: {
            total: 0,
            blocked: 0
          }
        }
      },
      users: [],
      routes: [
        {path: "/", method: "GET", hits: 3, apispec: {}}
      ],
      hostnames: []
    }
  end

  test "#flush includes the scans grouped by sink" do
    @collector.start(at: Time.at(1234567890))

    2.times { @collector.track_request(stub_request) }
    @collector.track_scan(stub_scan(sink: @sink))
    @collector.track_scan(stub_scan(sink: @sink))
    @collector.track_scan(stub_scan(sink: stub_sink(name: "another")))

    event = @collector.flush(at: Time.at(1234577890))

    assert_hash_subset_of event.as_json, {
      stats: {
        startedAt: 1234567890000,
        endedAt: 1234577890000,
        requests: {
          total: 2,
          aborted: 0,
          attacksDetected: {
            total: 0,
            blocked: 0
          }
        },
        sinks: {
          "test" => {
            total: 2,
            interceptorThrewError: 0,
            withoutContext: 0,
            attacksDetected: {
              total: 0,
              blocked: 0
            },
            compressedTimings: [
              {
                averageInMs: 1000,
                percentiles: {50 => 1000, 75 => 1000, 90 => 1000, 95 => 1000, 99 => 1000},
                compressedAt: 1234577890000
              }
            ]
          },
          "another" => {
            total: 1,
            interceptorThrewError: 0,
            withoutContext: 0,
            attacksDetected: {
              total: 0,
              blocked: 0
            },
            compressedTimings: [
              {
                averageInMs: 1000,
                percentiles: {50 => 1000, 75 => 1000, 90 => 1000, 95 => 1000, 99 => 1000},
                compressedAt: 1234577890000
              }
            ]
          }
        }
      },
      users: [],
      routes: [
        {path: "/", method: "GET", hits: 2, apispec: {}}
      ],
      hostnames: []
    }
  end

  test "#flush includes the attacks grouped by sink" do
    @collector.start(at: Time.at(1234567890))

    2.times { @collector.track_request(stub_request) }

    @collector.track_scan(stub_scan(sink: @sink))
    @collector.track_scan(stub_scan(sink: @sink))
    @collector.track_scan(stub_scan(sink: stub_sink(name: "another")))

    @collector.track_attack(stub_attack(sink: @sink, blocked: true))
    @collector.track_attack(stub_attack(sink: stub_sink(name: "another"), blocked: true))

    event = @collector.flush(at: Time.at(1234577890))

    assert_hash_subset_of event.as_json, {
      stats: {
        startedAt: 1234567890000,
        endedAt: 1234577890000,
        sinks: {
          "test" => {
            total: 2,
            interceptorThrewError: 0,
            withoutContext: 0,
            attacksDetected: {
              total: 1,
              blocked: 1
            },
            compressedTimings: [
              {
                averageInMs: 1000,
                percentiles: {50 => 1000, 75 => 1000, 90 => 1000, 95 => 1000, 99 => 1000},
                compressedAt: 1234577890000
              }
            ]
          },
          "another" => {
            total: 1,
            interceptorThrewError: 0,
            withoutContext: 0,
            attacksDetected: {
              total: 1,
              blocked: 1
            },
            compressedTimings: [
              {
                averageInMs: 1000,
                percentiles: {50 => 1000, 75 => 1000, 90 => 1000, 95 => 1000, 99 => 1000},
                compressedAt: 1234577890000
              }
            ]
          }
        },
        requests: {
          total: 2,
          aborted: 0,
          attacksDetected: {
            total: 2,
            blocked: 2
          }
        }
      },
      users: [],
      routes: [
        {path: "/", method: "GET", hits: 2, apispec: {}}
      ],
      hostnames: []
    }
  end

  test "#flush with a complete example" do
    @collector.start(at: Time.at(1234567890))

    2.times { @collector.track_request(stub_request("/")) }

    3.times do |i|
      @collector.track_outbound(stub_outbound(host: "example.com", port: 2000 + i))
    end

    @collector.track_user(stub_actor(
      id: "123", ip: "1.2.3.4", first_seen_at: Time.at(12345567890)
    ))
    @collector.track_user(stub_actor(
      id: "234", ip: "5.6.7.8", first_seen_at: Time.at(12334567890)
    ))

    @collector.track_scan(stub_scan(sink: @sink, duration: 2))
    @collector.track_scan(stub_scan(sink: @sink, duration: 3))
    @collector.track_scan(stub_scan(sink: @sink, duration: 1))
    @collector.track_attack(stub_attack(sink: @sink, blocked: true))

    event = @collector.flush(at: Time.at(1234577890))

    assert_hash_subset_of event.as_json, {
      stats: {
        startedAt: 1234567890000,
        endedAt: 1234577890000,
        sinks: {
          "test" => {
            total: 3,
            interceptorThrewError: 0,
            withoutContext: 0,
            attacksDetected: {
              total: 1,
              blocked: 1
            },
            compressedTimings: [{
              averageInMs: 2000,
              percentiles: {
                50 => 2000,
                75 => 3000,
                90 => 3000,
                95 => 3000,
                99 => 3000
              },
              compressedAt: 1234577890000
            }]
          }
        },
        requests: {
          total: 2,
          aborted: 0,
          attacksDetected: {
            total: 1,
            blocked: 1
          }
        }
      },
      routes: [{method: "GET", path: "/", hits: 2, apispec: {}}],
      users: [
        {
          id: "123",
          lastIpAddress: "1.2.3.4",
          firstSeenAt: 12345567890000,
          lastSeenAt: 12345567890000
        },
        {
          id: "234",
          lastIpAddress: "5.6.7.8",
          firstSeenAt: 12334567890000,
          lastSeenAt: 12334567890000
        }
      ],
      hostnames: [
        {hostname: "example.com", port: 2000},
        {hostname: "example.com", port: 2001},
        {hostname: "example.com", port: 2002}
      ]
    }
  end

  def stub_sink(name:)
    Aikido::Zen::Sink.new(name, operation: "test", scanners: [NOOP])
  end

  def stub_scan(sink: @sink, context: stub_context, duration: 1, attack: nil, errors: [])
    Aikido::Zen::Scan.new(sink: sink, context: context).tap do |scan|
      scan.instance_variable_set(:@performed, true)
      scan.instance_variable_set(:@attack, attack)
      scan.instance_variable_set(:@errors, errors)
      scan.instance_variable_set(:@duration, duration)
    end
  end

  def stub_attack(sink: @sink, context: stub_context, operation: "test", blocked: @config.blocking_mode?)
    Aikido::Zen::Attack.new(sink: sink, context: context, operation: operation).tap do |attack|
      attack.will_be_blocked! if blocked
    end
  end

  def stub_context(path = "/", env = {})
    env = Rack::MockRequest.env_for(path, {"REQUEST_METHOD" => "GET"}.merge(env))
    Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(env)
  end

  def stub_request(path = "/", env = {})
    stub_context(path, env).request
  end

  def stub_outbound(**opts)
    Aikido::Zen::OutboundConnection.new(**opts)
  end

  def stub_route(verb, path)
    Aikido::Zen::Route.new(verb: verb, path: path)
  end

  def stub_schema(**opts)
    Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: Aikido::Zen::Request::Schema::EMPTY_SCHEMA,
      query_schema: Aikido::Zen::Request::Schema::EMPTY_SCHEMA,
      auth_schema: Aikido::Zen::Request::Schema::AuthSchemas::NONE,
      **opts
    )
  end

  def stub_actor(first_seen_at: nil, seen_at: nil, ip: nil, **opts)
    opts = {seen_at: first_seen_at}.compact.merge(opts)
    Aikido::Zen::Actor.new(**opts).tap do |actor|
      update_attrs = {seen_at: seen_at, ip: ip}.compact
      actor.update(**update_attrs) if update_attrs.any?
    end
  end
end
