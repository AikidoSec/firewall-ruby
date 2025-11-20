# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::AttackWaveTest < ActiveSupport::TestCase
  class TestClock
    attr_reader :at

    def initialize(at: 0)
      @at = at
    end

    def advance(by = 1)
      @at += by
    end

    def call
      @at
    end
  end

  class DetectorTest < ActiveSupport::TestCase
    def env_for(path, env = {})
      env = Rack::MockRequest.env_for(path, env)
      Rails.application.env_config.merge(env)
    end

    DEFAULT_ENV = {"REMOTE_ADDR" => "1.2.3.4"}

    def build_context_for(path, env = {})
      env = env_for(path, env)
      Aikido::Zen::Context.from_rack_env(env)
    end

    def build_detector
      Aikido::Zen::AttackWave::Detector.new(clock: @clock)
    end

    def assert_attack_wave_in(context, detector: nil)
      detector ||= build_detector
      refute detector.attack_wave?(context)
      refute detector.attack_wave?(context)
      assert detector.attack_wave?(context)
    end

    def refute_attack_wave_in(context, detector: nil)
      detector ||= build_detector
      refute detector.attack_wave?(context)
      refute detector.attack_wave?(context)
      refute detector.attack_wave?(context)
    end

    def assert_attack_wave_for(path, env = {}, detector: nil)
      context = build_context_for(path, DEFAULT_ENV.merge(env))

      assert_attack_wave_in(context, detector: detector)
    end

    def refute_attack_wave_for(path, env = {}, detector: nil)
      context = build_context_for(path, DEFAULT_ENV.merge(env))

      refute_attack_wave_in(context, detector: detector)
    end

    def advance_clock
      @clock.advance(Aikido::Zen.config.attack_wave_min_time_between_events)
    end

    def setup
      @clock = TestClock.new

      Aikido::Zen.config.attack_wave_threshold = 3
    end

    test "can create detector" do
      detector = build_detector

      refute_nil detector
    end

    test "attack waves require an IP address" do
      # Create a context from an env without REMOTE_ADDR
      context = build_context_for("/.config")
      refute_attack_wave_in(context)
    end

    test "attack waves are detected once in the report period" do
      detector = build_detector
      5.times do
        assert_attack_wave_for("/.config", detector: detector)
        refute_attack_wave_for("/.config", detector: detector)
        refute_attack_wave_for("/.config", detector: detector)
        advance_clock
      end
    end

    test "attack waves from web scanners are detected when the path that includes suspicious file name is requested" do
      refute_attack_wave_for("/")
      refute_attack_wave_for("/safe")
      refute_attack_wave_for("/safe/path")
      assert_attack_wave_for("/.config")
      assert_attack_wave_for("/.gitignore")
      assert_attack_wave_for("/Dockerfile")
      assert_attack_wave_for("/aws-key.yaml")
      assert_attack_wave_for("/passwd")
    end

    test "attack waves from web scanners are detected when the path that includes a suspicious file extension is requested" do
      refute_attack_wave_for("/safe")
      refute_attack_wave_for("/file.safe")
      assert_attack_wave_for("/app.db")
      assert_attack_wave_for("/db.sql")
      assert_attack_wave_for("/local.env")
    end

    test "attack waves from web scanners are detected when the path that includes a suspicious directory name is requested" do
      refute_attack_wave_for("/")
      refute_attack_wave_for("/safe")
      refute_attack_wave_for("/safe/path")
      assert_attack_wave_for("/../../etc/hostname")
      assert_attack_wave_for("/.ssh/authorized_keys")
      assert_attack_wave_for("/.git/config")
      assert_attack_wave_for("~/.ssh/known_hosts")
    end

    test "attack waves from web scanners are detected when the method is suspicious" do
      refute_attack_wave_for("/", {method: "SAFE"}, detector: nil)
      assert_attack_wave_for("/", {method: "BADMETHOD"}, detector: nil)
      assert_attack_wave_for("/", {method: "BADHTTPMETHOD"}, detector: nil)
      assert_attack_wave_for("/", {method: "BADDATA"}, detector: nil)
    end

    test "attack waves from web scanners are detected when the query includes a suspicious SQL keyword" do
      context = build_context_for("/?q=safe", DEFAULT_ENV)
      refute_attack_wave_in(context)

      context = build_context_for("/", DEFAULT_ENV.merge({
        :method => "POST",
        "HTTP_COOKIE" => "c1=foo; c2=bar; c3=baz"
      }))
      refute_attack_wave_in(context)

      context = build_context_for("/", DEFAULT_ENV.merge({
        params: {q: "SAFE PARAMETER"}
      }))
      refute_attack_wave_in(context)

      context = build_context_for("/", DEFAULT_ENV.merge({
        params: {q: "MD5("}
      }))
      refute_attack_wave_in(context)

      context = build_context_for("/", DEFAULT_ENV.merge({
        params: {q: "1'='1"}
      }))
      assert_attack_wave_in(context)

      context = build_context_for("/", DEFAULT_ENV.merge({
        params: {q: "SELECT * FROM"}
      }))
      assert_attack_wave_in(context)

      context = build_context_for("/", DEFAULT_ENV.merge({
        params: {q: "SELECT (CASE WHEN"}
      }))
      assert_attack_wave_in(context)
    end
  end
end
