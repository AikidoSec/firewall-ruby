# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::StatsTest < ActiveSupport::TestCase
  setup do
    @config = Aikido::Agent.config

    @stats = Aikido::Agent::Stats.new(@config)
    @sink = stub_sink(name: "test")
  end

  def stub_sink(name:)
    Aikido::Firewall::Sink.new(name, scanners: [NOOP])
  end

  def stub_scan(sink: @sink, request: stub_request, duration: 1, attack: nil, errors: [])
    Aikido::Firewall::Scan.new(sink: sink, request: request).tap do |scan|
      scan.instance_variable_set(:@performed, true)
      scan.instance_variable_set(:@attack, attack)
      scan.instance_variable_set(:@errors, errors)
      scan.instance_variable_set(:@duration, duration)
    end
  end

  def stub_attack(sink: @sink, request: stub_request)
    Aikido::Firewall::Attack.new(sink: sink, request: request)
  end

  def stub_request
    Aikido::Agent::Request.new({})
  end

  test "#start tracks the time at which stats started being collected" do
    time = Time.at(1234567890)

    @stats.start(time)

    assert_equal time, @stats.started_at
  end

  test "#add_request increments the number of requests" do
    assert_changes -> { @stats.requests }, from: 0, to: 2 do
      @stats.add_request(stub_request)
      @stats.add_request(stub_request)
    end
  end

  test "#add_scan increments the total number of scans for the sink" do
    assert_changes -> { @stats.sinks[@sink.name].scans }, from: 0, to: 2 do
      @stats.add_scan(stub_scan(sink: @sink))
      @stats.add_scan(stub_scan(sink: @sink))
    end
  end

  test "#add_scan increments the number of errors if a scan caught an internal error" do
    assert_changes -> { @stats.sinks[@sink.name].errors }, from: 0, to: 1 do
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

      expected = Aikido::Agent::Stats::SinkStats::CompressedTiming.new(
        2, {50 => 2, 75 => 3, 90 => 3, 95 => 3, 99 => 3}, Time.now.utc
      )

      assert_equal [expected], stats.compressed_timings
    end
  end

  test "#add_attack increments the total number of attacks detected for the sink" do
    assert_changes -> { @stats.sinks[@sink.name].attacks }, from: 0, to: 2 do
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
    end
  end

  test "#add_attack tracks how many attacks is told were blocked per sink" do
    assert_changes -> { @stats.sinks[@sink.name].blocked_attacks }, from: 0, to: 1 do
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
      @stats.add_attack(stub_attack(sink: @sink), being_blocked: false)
    end
  end

  test "#as_json serializes an empty stats set" do
    @stats.start(Time.at(1234567890))

    expected = {
      startedAt: 1234567890000,
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
    3.times { @stats.add_request(stub_request) }

    expected = {
      startedAt: 1234567890000,
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
    2.times { @stats.add_request(stub_request) }

    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    expected = {
      startedAt: 1234567890000,
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
    2.times { @stats.add_request(stub_request) }

    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink, errors: [RuntimeError.new]))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    expected = {
      startedAt: 1234567890000,
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
    2.times { @stats.add_request(stub_request) }

    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: @sink))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another")))

    @stats.add_attack(stub_attack(sink: @sink), being_blocked: true)
    @stats.add_attack(stub_attack(sink: stub_sink(name: "another")), being_blocked: true)

    expected = {
      startedAt: 1234567890000,
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
    2.times { @stats.add_request(stub_request) }

    @stats.add_scan(stub_scan(sink: @sink, duration: 2))
    @stats.add_scan(stub_scan(sink: @sink, duration: 3))
    @stats.add_scan(stub_scan(sink: @sink, duration: 1))
    @stats.add_scan(stub_scan(sink: stub_sink(name: "another"), duration: 1))

    freeze_time do
      @stats.sinks.each_value(&:compress_timings)

      expected = {
        startedAt: 1234567890000,
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
end
