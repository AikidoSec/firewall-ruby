# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::AttackWaveProtectorTest < ActiveSupport::TestCase
  def env_for(path, env = {})
    env = Rack::MockRequest.env_for(path, env)
    Rails.application.env_config.merge(env)
  end

  def build_context_for(path, env = {})
    env = env_for(path, env)
    Aikido::Zen::Context.from_rack_env(env)
  end

  DEFAULT_ENV = {"REMOTE_ADDR" => "1.2.3.4"}

  setup do
    Aikido::Zen.config.attack_wave_threshold = 3
  end

  test "#call detects attack waves, collects statistics, and reports the event" do
    app = Minitest::Mock.new
    app.expect :call, [200, {}, ["OK"]], [Hash]

    zen = Minitest::Mock.new

    middleware = Aikido::Zen::Middleware::AttackWaveProtector.new(app, zen: zen)

    context = build_context_for("/.config", DEFAULT_ENV)

    zen.expect :attack_wave_detector, Aikido::Zen.attack_wave_detector
    middleware.protect(context)

    zen.expect :attack_wave_detector, Aikido::Zen.attack_wave_detector
    middleware.protect(context)

    agent = Minitest::Mock.new
    agent.expect(:report, nil) { |arg| arg.is_a?(Aikido::Zen::Events::AttackWave) }

    zen.expect :attack_wave_detector, Aikido::Zen.attack_wave_detector
    zen.expect :agent, agent
    zen.expect(:track_attack_wave, nil) { |arg| arg.is_a?(Aikido::Zen::Events::AttackWave) }
    middleware.protect(context)

    assert_mock zen
  end
end
