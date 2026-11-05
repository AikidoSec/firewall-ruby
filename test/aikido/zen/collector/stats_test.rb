# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Collector::StatsTest < ActiveSupport::TestCase
  include StubsCurrentContext

  setup do
    @stats = Aikido::Zen::Collector::Stats.new
    @sink = stub_sink(name: "test")
  end

  def stub_sink(name:, kind: "test_op")
    Aikido::Zen::Sink.new(name, kind, operation: "test", scanners: [NOOP])
  end

  def stub_scan(sink: @sink, context: stub_context, attack: nil, errors: [])
    Aikido::Zen::Scan.new(sink: sink, context: context).tap do |scan|
      scan.instance_variable_set(:@performed, true)
      scan.instance_variable_set(:@attack, attack)
      scan.instance_variable_set(:@errors, errors)
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

  test "#empty? is false after a user agent is tracked" do
    @stats.add_user_agent(["adsbot_google"])
    refute @stats.empty?
    assert @stats.any?
  end

  test "#empty? is false after an attack wave is tracked" do
    @stats.add_attack_wave(being_blocked: false)
    refute @stats.empty?
    assert @stats.any?
  end

  test "#empty? is false after a blocked attack wave is tracked" do
    @stats.add_attack_wave(being_blocked: true)
    refute @stats.empty?
    assert @stats.any?
  end

  test "#empty? is false after a scan is tracked" do
    scan = stub_scan
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    refute @stats.empty?
    assert @stats.any?
  end

  test "#empty? is false after an attack is tracked" do
    @stats.add_attack(@sink.name, @sink.kind, being_blocked: true)
    refute_empty @stats
  end

  test "#add_request increments the number of requests" do
    assert_difference "@stats.requests", +2 do
      @stats.add_request
      @stats.add_request
    end
  end

  test "#add_user_agent increments the the total number of user agents" do
    assert_difference "@stats.user_agents.length", +7 do
      @stats.add_user_agent(["adsbot_google"])
      @stats.add_user_agent(["adsbot_google"])

      @stats.add_user_agent(["githubcopilotchat"])

      # Multiple user agent keys are incremented if multiple user agent keys match
      # (currently theoretical).

      @stats.add_user_agent(["custom_a1", "custom_a2"])

      @stats.add_user_agent(["custom_b1", "custom_b2", "custom_b3"])
    end

    assert_equal @stats.user_agents["adsbot_google"], 2

    assert_equal @stats.user_agents["githubcopilotchat"], 1

    assert_equal @stats.user_agents["custom_a1"], 1
    assert_equal @stats.user_agents["custom_a2"], 1
    assert_equal @stats.user_agents["custom_b1"], 1
    assert_equal @stats.user_agents["custom_b2"], 1
    assert_equal @stats.user_agents["custom_b3"], 1
  end

  test "#add_scan increments the total number of scans for the sink" do
    assert_difference -> { @stats.sinks[@sink.name].scans }, +2 do
      scan = stub_scan(sink: @sink)
      @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

      scan = stub_scan(sink: @sink)
      @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)
    end
  end

  test "#add_scan increments the number of errors if a scan caught an internal error" do
    assert_difference -> { @stats.sinks[@sink.name].errors }, +1 do
      scan = stub_scan(sink: @sink, errors: [RuntimeError.new])
      @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

      scan = stub_scan(sink: @sink)
      @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)
    end
  end

  test "#add_attack increments the total number of attacks detected for the sink" do
    assert_difference -> { @stats.sinks[@sink.name].attacks }, +2 do
      @stats.add_attack(@sink.name, @sink.kind, being_blocked: true)
      @stats.add_attack(@sink.name, @sink.kind, being_blocked: true)
    end
  end

  test "#add_attack tracks how many attacks is told were blocked per sink" do
    assert_difference -> { @stats.sinks[@sink.name].blocked_attacks }, +1 do
      @stats.add_attack(@sink.name, @sink.kind, being_blocked: true)
      @stats.add_attack(@sink.name, @sink.kind, being_blocked: false)
    end
  end

  test "#as_json includes the collection period timestamps" do
    @stats.start(Time.at(1234567890))
    @stats.ended_at = Time.at(1234577890)

    assert_hash_subset_of @stats.as_json, {
      "startedAt" => 1234567890000,
      "endedAt" => 1234577890000
    }
  end

  test "#as_json includes the number of requests" do
    3.times { @stats.add_request }

    assert_hash_subset_of @stats.as_json, {
      "requests" => {
        "total" => 3,
        "aborted" => 0,
        "rateLimited" => 0,
        "attacksDetected" => {
          "total" => 0,
          "blocked" => 0
        },
        "attackWaves" => {
          "total" => 0,
          "blocked" => 0
        }
      }
    }
  end

  test "#as_json includes the scans grouped by sink" do
    scan = stub_scan(sink: @sink)
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    scan = stub_scan(sink: @sink)
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    scan = stub_scan(sink: stub_sink(name: "another"))
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    assert_hash_subset_of @stats.as_json, {
      "operations" => {
        "test" => {
          "kind" => "test_op",
          "total" => 2,
          "interceptorThrewError" => 0,
          "withoutContext" => 0,
          "attacksDetected" => {
            "total" => 0,
            "blocked" => 0
          }
        },
        "another" => {
          "kind" => "test_op",
          "total" => 1,
          "interceptorThrewError" => 0,
          "withoutContext" => 0,
          "attacksDetected" => {
            "total" => 0,
            "blocked" => 0
          }
        }
      }
    }
  end

  test "#as_json includes the number of scans that raised an error" do
    scan = stub_scan(sink: @sink)
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    scan = stub_scan(sink: @sink, errors: [RuntimeError.new])
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    scan = stub_scan(sink: stub_sink(name: "another"))
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    assert_hash_subset_of @stats.as_json, {
      "operations" => {
        "test" => {
          "kind" => "test_op",
          "total" => 2,
          "interceptorThrewError" => 1,
          "withoutContext" => 0,
          "attacksDetected" => {
            "total" => 0,
            "blocked" => 0
          }
        },
        "another" => {
          "kind" => "test_op",
          "total" => 1,
          "interceptorThrewError" => 0,
          "withoutContext" => 0,
          "attacksDetected" => {
            "total" => 0,
            "blocked" => 0
          }
        }
      }
    }
  end

  test "#as_json includes the attacks grouped by sink" do
    scan = stub_scan(sink: @sink)
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    scan = stub_scan(sink: @sink)
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    another = stub_sink(name: "another")
    scan = stub_scan(sink: another)
    @stats.add_scan(scan.sink.name, scan.sink.kind, has_errors: scan.errors?)

    @stats.add_attack(@sink.name, @sink.kind, being_blocked: true)
    @stats.add_attack(another.name, another.kind, being_blocked: true)

    assert_hash_subset_of @stats.as_json, {
      "operations" => {
        "test" => {
          "kind" => "test_op",
          "total" => 2,
          "interceptorThrewError" => 0,
          "withoutContext" => 0,
          "attacksDetected" => {
            "total" => 1,
            "blocked" => 1
          }
        },
        "another" => {
          "kind" => "test_op",
          "total" => 1,
          "interceptorThrewError" => 0,
          "withoutContext" => 0,
          "attacksDetected" => {
            "total" => 1,
            "blocked" => 1
          }
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
end
