# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::AttackWaveTest < ActiveSupport::TestCase
  class HelpersTest < ActiveSupport::TestCase
    def context_for(path, env = {})
      Aikido::Zen::Context.from_rack_env(Rack::MockRequest.env_for(path, env))
    end

    test "suspicious_path? returns true for foreign extension with 404 status" do
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/admin.php", 404)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/app.jsp", 404)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/page.jspx", 404)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/index.php3", 404)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/index.php4", 404)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/index.php5", 404)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/index.phtml", 404)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/Hello.java", 404)
    end

    test "suspicious_path? returns false for foreign extension with non-404 status" do
      refute Aikido::Zen::AttackWave::Helpers.suspicious_path?("/admin.php", 200)
      refute Aikido::Zen::AttackWave::Helpers.suspicious_path?("/app.jsp", 200)
      refute Aikido::Zen::AttackWave::Helpers.suspicious_path?("/admin.php", 301)
      refute Aikido::Zen::AttackWave::Helpers.suspicious_path?("/admin.php", 500)
      refute Aikido::Zen::AttackWave::Helpers.suspicious_path?("/admin.php", nil)
    end

    test "suspicious_path? still returns true for always-suspicious extensions regardless of status" do
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/backup.sql", 200)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/data.db", 200)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/dump.bak", 200)
    end

    test "suspicious_path? still returns true for suspicious file names regardless of status" do
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/.gitconfig", 200)
      assert Aikido::Zen::AttackWave::Helpers.suspicious_path?("/wp-config.php", 200)
    end

    test "sample_for builds a sample from the request's verb and path" do
      context = context_for("/.config?q=1", "REMOTE_ADDR" => "1.2.3.4")

      sample = Aikido::Zen::AttackWave::Helpers.sample_for(context)

      assert_equal "GET", sample.verb
      assert_equal "/.config?q=1", sample.path
    end

    test "sample_for uses the original path when Rails has rewritten PATH_INFO for an exceptions_app" do
      context = context_for("/.config?q=1",
        "REMOTE_ADDR" => "1.2.3.4",
        "action_dispatch.original_path" => "/.config",
        "PATH_INFO" => "/404")

      sample = Aikido::Zen::AttackWave::Helpers.sample_for(context)

      assert_equal "/.config?q=1", sample.path
    end
  end

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

    # Aikido::Zen orchestrates attack wave detection so that it works in the
    # main process and worker processes. The detector under test is stubbed
    # as the local attack_wave_detector. No worker process client is present.
    def attack_wave?(context, detector = build_detector)
      Aikido::Zen.stub(:attack_wave_detector, detector) do
        Aikido::Zen.detect_attack_wave(context)
      end
    end

    def assert_attack_wave_in(context, detector: nil)
      detector ||= build_detector
      refute attack_wave?(context, detector)
      refute attack_wave?(context, detector)
      assert attack_wave?(context, detector)
    end

    def refute_attack_wave_in(context, detector: nil)
      detector ||= build_detector
      refute attack_wave?(context, detector)
      refute attack_wave?(context, detector)
      refute attack_wave?(context, detector)
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

    test "collects multiple samples" do
      detector ||= build_detector

      context = build_context_for("/.config", DEFAULT_ENV)
      refute attack_wave?(context, detector)

      context = build_context_for("/.git/config", DEFAULT_ENV)
      refute attack_wave?(context, detector)

      context = build_context_for("/.ssh/known_hosts", DEFAULT_ENV)
      assert attack_wave?(context, detector)

      samples = detector.samples[context.request.client_ip]

      assert 3, samples.size

      expected = [
        {"method" => "GET", "url" => "/.config"},
        {"method" => "GET", "url" => "/.git/config"},
        {"method" => "GET", "url" => "/.ssh/known_hosts"}
      ]

      assert_equal expected, samples.as_json
    end

    test "#flagged? returns false until the threshold is crossed via #record" do
      detector = build_detector
      sample = Aikido::Zen::AttackWave::Sample.new(verb: "GET", path: "/.config")

      refute detector.flagged?("1.2.3.4")

      detector.record("1.2.3.4", sample)
      refute detector.flagged?("1.2.3.4")

      detector.record("1.2.3.4", sample)
      refute detector.flagged?("1.2.3.4")

      detector.record("1.2.3.4", sample)
      assert detector.flagged?("1.2.3.4")
    end

    test "#flag! marks a client IP as flagged directly" do
      detector = build_detector

      refute detector.flagged?("1.2.3.4")

      detector.flag!("1.2.3.4")

      assert detector.flagged?("1.2.3.4")
    end

    test "#record shares state with .detect_attack_wave so a delegated recording is reflected locally" do
      detector = build_detector
      sample = Aikido::Zen::AttackWave::Sample.new(verb: "GET", path: "/.config")

      refute detector.record("1.2.3.4", sample)
      refute detector.record("1.2.3.4", sample)
      assert detector.record("1.2.3.4", sample)

      refute_attack_wave_for("/.config", detector: detector)
    end
  end
end
