# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Collector::StatsTest < ActiveSupport::TestCase
  include StubsCurrentContext

  setup do
    @config = Aikido::Zen.config

    @stats = Aikido::Zen::Collector::Stats.new(@config)
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
    env["REQUEST_METHOD"] ||= "GET"
    Aikido::Zen::Context.from_rack_env(env)
  end

  def stub_outbound(**opts)
    Aikido::Zen::OutboundConnection.new(**opts)
  end

  def stub_actor(seen_at: nil, ip: nil, **opts)
    Aikido::Zen::Actor.new(**opts).tap do |actor|
      update_attrs = {seen_at: seen_at, ip: ip}.compact
      actor.update(**update_attrs) if update_attrs.any?
    end
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
    @stats.add_request
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
    assert_difference "@stats.requests", +2 do
      @stats.add_request
      @stats.add_request
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

      expected = Aikido::Zen::Collector::SinkStats::CompressedTiming.new(
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

  test "#as_json includes the collection period timestamps" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    assert_hash_subset_of @stats.as_json, {
      startedAt: 1234567890000,
      endedAt: 1234577890000
    }
  end

  test "#as_json includes the number of requests" do
    3.times { @stats.add_request }

    assert_hash_subset_of @stats.as_json, {
      requests: {
        total: 3,
        aborted: 0,
        attacksDetected: {
          total: 0,
          blocked: 0
        }
      }
    }
  end

  test "#as_json includes the scans grouped by sink" do
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    assert_hash_subset_of @stats.as_json, {
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
  end

  test "#as_json includes the number of scans that raised an error" do
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink, errors: [RuntimeError.new]))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    assert_hash_subset_of @stats.as_json, {
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
  end

  test "#as_json includes the attacks grouped by sink" do
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
    @stats.add_attack(stub_attack(sink: stub_sink(name: "another")), being_blocked: true)

    assert_hash_subset_of @stats.as_json, {
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
  end

  test "#as_json includes the compressed timings grouped by sink" do
    @stats.add_scan(stub_scan(sink: @sink, duration: 2))
    @stats.add_scan(stub_scan(sink: @sink, duration: 3))
    @stats.add_scan(stub_scan(sink: @sink, duration: 1))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another"), duration: 1))
    @stats.sinks.each_value { |s| s.compress_timings(at: Time.at(1234577890)) }

    assert_hash_subset_of @stats.as_json, {
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
            compressedAt: 1234577890000
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
            compressedAt: 1234577890000
          }]
        }
      }
    }
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
end
