# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::StatsTest < ActiveSupport::TestCase
  include StubsCurrentContext

  setup do
    @config = Aikido::Zen.config

    @stats = Aikido::Zen::Stats.new(@config)
    @sink = stub_sink(name: "test")
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

  def stub_attack(sink: @sink, context: stub_context, operation: "test")
    Aikido::Zen::Attack.new(sink: sink, context: context, operation: operation)
  end

  def stub_context(env = {})
    Aikido::Zen::Context.from_rack_env(env)
  end

  def stub_outbound(**opts)
    Aikido::Zen::OutboundConnection.new(**opts)
  end

  def stub_actor(**opts)
    Aikido::Zen::Actor.new(**opts)
  end

  test "#start tracks the time at which stats started being collected" do
    time = Time.at(1234567890)

    @stats.start(time)

    assert_equal time, @stats.started_at
  end

  test "#empty? is true if no data has been recorded" do
    @stats.start(time)
    assert @stats.empty?
    refute @stats.any?
  end

  test "#empty? is false after a request is tracked" do
    @stats.add_request(stub_context.request)
    refute @stats.empty?
    assert @stats.any?
  end

  test "#empty? is false after a scan is tracked" do
    @stats.add_scan(stub_scan)
    refute @stats.empty?
    assert @stats.any?
  end

  test "#empty? is false after an attack is tracked" do
    @stats.add_attack(stub_attack, being_blocked: true)
    refute_empty @stats
  end

  test "#add_request increments the number of requests" do
    assert_difference -> { @stats.requests }, +2 do
      @stats.add_request(stub_context.request)
      @stats.add_request(stub_context.request)
    end
  end

  test "#add_request tracks how many times the given route was visited" do
    ctx_1 = stub_context(Rack::MockRequest.env_for("/get"))
    route_1 = Aikido::Zen::Route.new(verb: "GET", path: "/get")

    ctx_2 = stub_context(Rack::MockRequest.env_for("/post", "REQUEST_METHOD" => "POST"))
    route_2 = Aikido::Zen::Route.new(verb: "POST", path: "/post")

    assert_difference -> { @stats.routes[route_1].hits }, +2 do
      assert_difference -> { @stats.routes[route_2].hits }, +1 do
        @stats.add_request(ctx_1.request)
        @stats.add_request(ctx_2.request)
        @stats.add_request(ctx_1.request)
      end
    end
  end

  test "#add_scan increments the total number of scans for the sink" do
    assert_difference -> { @stats.sinks[@sink.name].scans }, +2 do
      @stats.add_scan(stub_scan(sink: @sink))
      @stats.add_scan(stub_scan(sink: @sink))
    end
  end

  test "#add_scan increments the number of errors if a scan caught an internal error" do
    assert_difference -> { @stats.sinks[@sink.name].errors }, +1 do
      @stats.add_scan(stub_scan(sink: @sink, errors: [RuntimeError.new]))
      @stats.add_scan(stub_scan(sink: @sink))
    end
  end

  test "#add_scan tracks the time it took to run the scan" do
    timings = @stats.sinks[@sink.name].timings

    assert timings.empty?

    @stats.add_scan(stub_scan(sink: @sink, duration: 0.03))
    @stats.add_scan(stub_scan(sink: @sink, duration: 0.05))

    assert_includes timings, 0.03
    assert_includes timings, 0.05
  end

  test "#add_scan will compress timings before overflowing the set" do
    @config.max_performance_samples = 3

    stats = @stats.sinks[@sink.name]

    freeze_time do
      @stats.add_scan(stub_scan(sink: @sink, duration: 2))
      @stats.add_scan(stub_scan(sink: @sink, duration: 3))
      @stats.add_scan(stub_scan(sink: @sink, duration: 1))
      @stats.add_scan(stub_scan(sink: @sink, duration: 4))

      # The last value is kept in the raw timings list
      assert_equal Set.new([4]), stats.timings

      expected = Aikido::Zen::Stats::SinkStats::CompressedTiming.new(
        2, {50 => 2, 75 => 3, 90 => 3, 95 => 3, 99 => 3}, Time.now.utc
      )

      assert_equal Set.new([expected]), stats.compressed_timings.to_set
    end
  end

  test "#add_attack increments the total number of attacks detected for the sink" do
    assert_difference -> { @stats.sinks[@sink.name].attacks }, +2 do
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
    end
  end

  test "#add_attack tracks how many attacks is told were blocked per sink" do
    assert_difference -> { @stats.sinks[@sink.name].blocked_attacks }, +1 do
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: false)
    end
  end

  test "#add_outbound tracks which connections have been made" do
    c1 = stub_outbound(host: "example.com", port: 80)
    c2 = stub_outbound(host: "example.com", port: 443)

    assert_difference -> { @stats.outbound_connections.size }, +2 do
      @stats.add_outbound(c1)
      @stats.add_outbound(c2)
    end

    assert_includes @stats.outbound_connections, c1
    assert_includes @stats.outbound_connections, c2
  end

  test "#add_outbound doesn't count the same host/port pair more than once" do
    conn = stub_outbound(host: "example.com", port: 443)

    assert_difference -> { @stats.outbound_connections.size }, +1 do
      @stats.add_outbound(conn)
      @stats.add_outbound(conn)
    end

    assert_includes @stats.outbound_connections, conn
  end

  test "#add_outbound limits the amount of connections tracked" do
    conn = stub_outbound(host: "example.com", port: 0)
    @stats.add_outbound(conn)

    assert_includes @stats.outbound_connections, conn

    @config.max_outbound_connections.times do |idx|
      @stats.add_outbound(stub_outbound(host: "test.com", port: idx))
    end

    assert_equal @config.max_outbound_connections, @stats.outbound_connections.size
    refute_includes @stats.outbound_connections, conn
  end

  test "#add_user tracks which users have visited the app" do
    initial_time = Time.utc(2024, 9, 1, 16, 20, 42)

    u1 = stub_actor(id: "123", name: "Alice", seen_at: initial_time, ip: "1.2.3.4")
    u2 = stub_actor(id: "345", name: "Bob", seen_at: initial_time + 5, ip: "2.3.4.5")

    assert_difference -> { @stats.users.size }, +2 do
      @stats.add_user(u1)
      @stats.add_user(u2)
    end

    assert_includes @stats.users, u1
    assert_includes @stats.users, u2
  end

  test "#add_user doesn't count a user more than once" do
    initial_time = Time.utc(2024, 9, 1, 16, 20, 42)

    user = stub_actor(id: "123", name: "Alice", seen_at: initial_time, ip: "1.2.3.4")

    assert_difference -> { @stats.users.size }, +1 do
      @stats.add_user(user)
      @stats.add_user(user)
    end
  end

  test "#add_user updates the user's last_seen_at when the user is added multiple times" do
    user = stub_actor(id: "123", seen_at: Time.utc(2024, 9, 1, 16, 20, 42))
    @stats.add_user(user)

    travel_to(user.last_seen_at + 20) do
      assert_difference "user.last_seen_at", +20 do
        same_user_in_diff_request = stub_actor(id: user.id)
        @stats.add_user(same_user_in_diff_request)
      end
    end
  end

  test "#add_user updates the user's ip to the current context's request IP" do
    user = stub_actor(id: "123", ip: "1.2.3.4")
    @stats.add_user(user)

    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "6.7.8.9")
    with_context Aikido::Zen::Context.from_rack_env(env) do
      assert_changes "user.ip", to: "6.7.8.9" do
        same_user_in_diff_request = stub_actor(id: user.id)
        @stats.add_user(same_user_in_diff_request)
      end
    end
  end

  test "#as_json serializes an empty stats set" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    expected = {
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
    }

    assert_equal expected, @stats.as_json
  end

  test "#as_json includes the number of requests" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    3.times { @stats.add_request(stub_context.request) }

    expected = {
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
    }

    assert_equal expected, @stats.as_json
  end

  test "#as_json includes the scans grouped by sink" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    2.times { @stats.add_request(stub_context.request) }

    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    expected = {
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
          compressedTimings: []
        },
        "another" => {
          total: 1,
          interceptorThrewError: 0,
          withoutContext: 0,
          attacksDetected: {
            total: 0,
            blocked: 0
          },
          compressedTimings: []
        }
      }
    }

    assert_equal expected, @stats.as_json
  end

  test "#as_json includes the number of scans that raised an error" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    2.times { @stats.add_request(stub_context.request) }

    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink, errors: [RuntimeError.new]))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    expected = {
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
          interceptorThrewError: 1,
          withoutContext: 0,
          attacksDetected: {
            total: 0,
            blocked: 0
          },
          compressedTimings: []
        },
        "another" => {
          total: 1,
          interceptorThrewError: 0,
          withoutContext: 0,
          attacksDetected: {
            total: 0,
            blocked: 0
          },
          compressedTimings: []
        }
      }
    }

    assert_equal expected, @stats.as_json
  end

  test "#as_json includes the attacks grouped by sink" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    2.times { @stats.add_request(stub_context.request) }

    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
    @stats.add_attack(stub_attack(sink: stub_sink(name: "another")), being_blocked: true)

    expected = {
      startedAt: 1234567890000,
      endedAt: 1234577890000,
      requests: {
        total: 2,
        aborted: 0,
        attacksDetected: {
          total: 2,
          blocked: 2
        }
      },
      sinks: {
        "test" => {
          total: 2,
          interceptorThrewError: 0,
          withoutContext: 0,
          attacksDetected: {
            total: 1,
            blocked: 1
          },
          compressedTimings: []
        },
        "another" => {
          total: 1,
          interceptorThrewError: 0,
          withoutContext: 0,
          attacksDetected: {
            total: 1,
            blocked: 1
          },
          compressedTimings: []
        }
      }
    }

    assert_equal expected, @stats.as_json
  end

  test "#as_json includes the compressed timings grouped by sink" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    2.times { @stats.add_request(stub_context.request) }

    @stats.add_scan(stub_scan(sink: @sink, duration: 2))
    @stats.add_scan(stub_scan(sink: @sink, duration: 3))
    @stats.add_scan(stub_scan(sink: @sink, duration: 1))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another"), duration: 1))

    freeze_time do
      @stats.sinks.each_value(&:compress_timings)

      expected = {
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
            total: 3,
            interceptorThrewError: 0,
            withoutContext: 0,
            attacksDetected: {
              total: 0,
              blocked: 0
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
              compressedAt: Time.now.to_i * 1000
            }]
          },
          "another" => {
            total: 1,
            interceptorThrewError: 0,
            withoutContext: 0,
            attacksDetected: {
              total: 0,
              blocked: 0
            },
            compressedTimings: [{
              averageInMs: 1000,
              percentiles: {
                50 => 1000,
                75 => 1000,
                90 => 1000,
                95 => 1000,
                99 => 1000
              },
              compressedAt: Time.now.to_i * 1000
            }]
          }
        }
      }

      assert_equal expected, @stats.as_json
    end
  end

  test "#flush sets ended_at and freezes the stats" do
    @stats.start(Time.at(1234567890))

    flushed = @stats.flush(at: Time.at(1234577890))

    assert flushed.frozen?
    assert_same @stats, flushed
    assert_equal Time.at(1234577890), flushed.ended_at
  end

  test "#flush compresses all timing metrics" do
    @stats.start(Time.at(1234567890))

    raw_timings = @stats.sinks[@sink.name].timings
    compressed_timings = @stats.sinks[@sink.name].compressed_timings

    @stats.add_scan(stub_scan(sink: @sink, duration: 2))
    @stats.add_scan(stub_scan(sink: @sink, duration: 3))
    @stats.add_scan(stub_scan(sink: @sink, duration: 1))

    assert_difference -> { compressed_timings.size }, +1 do
      assert_difference -> { raw_timings.size }, -3 do
        @stats.flush
      end
    end
  end

  test "#as_json after flushing includes all the data" do
    @stats.start(Time.at(1234567890))

    2.times do
      env = Rack::MockRequest.env_for("/")
      @stats.add_request(stub_context(env).request)
    end

    3.times do |i|
      @stats.add_outbound(stub_outbound(host: "example.com", port: i))
    end

    @stats.add_user(stub_actor(id: "123"))
    @stats.add_user(stub_actor(id: "234"))

    @stats.add_scan(stub_scan(sink: @sink, duration: 2))
    @stats.add_scan(stub_scan(sink: @sink, duration: 3))
    @stats.add_scan(stub_scan(sink: @sink, duration: 1))
    @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)

    freeze_time do
      expected_stats = {
        startedAt: 1234567890000,
        endedAt: 1234577890000,
        requests: {
          total: 2,
          aborted: 0,
          attacksDetected: {
            total: 1,
            blocked: 1
          }
        },
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
              compressedAt: Time.now.to_i * 1000
            }]
          }
        }
      }

      flushed = @stats.flush(at: Time.at(1234577890))
      assert_equal expected_stats, flushed.as_json
    end
  end
end
