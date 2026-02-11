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

  def build_attack_wave(context)
    client_ip = context.request.client_ip

    request = Aikido::Zen::AttackWave::Request.new(
      ip_address: client_ip,
      user_agent: context.request.user_agent,
      source: context.request.framework
    )

    samples = []

    context.request.then do |request|
      samples << Aikido::Zen::AttackWave::Sample.new(
        verb: request.request_method,
        path: request.fullpath
      )
    end

    attack = Aikido::Zen::AttackWave::Attack.new(
      samples: samples,
      user: context.request.actor
    )

    Aikido::Zen::Events::AttackWave.new(
      request: request,
      attack: attack
    )
  end

  setup do
    Aikido::Zen.config.attack_wave_threshold = 3

    @settings = Aikido::Zen.runtime_settings
  end

  test "#call detects attack waves, collects statistics, and reports the event" do
    app = Minitest::Mock.new
    zen = Minitest::Mock.new
    agent = Minitest::Mock.new

    middleware = Aikido::Zen::Middleware::AttackWaveProtector.new(app, zen: zen)

    context = build_context_for("/.config", DEFAULT_ENV)

    zen.expect :current_context, context
    zen.expect :attack_wave_detector, Aikido::Zen.attack_wave_detector
    app.expect(:call, [200, {}, ["OK"]], [Hash])
    middleware.call({})

    assert_mock zen
    assert_mock app

    zen.expect :current_context, context
    zen.expect :attack_wave_detector, Aikido::Zen.attack_wave_detector
    app.expect(:call, [200, {}, ["OK"]], [Hash])
    middleware.call({})

    assert_mock zen
    assert_mock app

    zen.expect :current_context, context
    2.times { zen.expect :attack_wave_detector, Aikido::Zen.attack_wave_detector }

    attack_wave = build_attack_wave(context)

    zen.expect(:track_attack_wave, nil, [attack_wave])
    zen.expect :agent, agent
    agent.expect(:report, nil, [attack_wave])
    app.expect(:call, [200, {}, ["OK"]], [Hash])
    middleware.call({})

    assert_mock zen
    assert_mock agent
    assert_mock app
  end

  test "#call detects attack waves, collects statistics, and reports the event, unless the request IP is an bypassed IP" do
    @settings.bypassed_ips = Aikido::Zen::RuntimeSettings::IPSet.from_json(["1.2.3.4"])

    app = Minitest::Mock.new
    zen = Minitest::Mock.new

    middleware = Aikido::Zen::Middleware::AttackWaveProtector.new(app, zen: zen)

    context = build_context_for("/.config", DEFAULT_ENV)

    zen.expect :current_context, context
    app.expect(:call, [200, {}, ["OK"]], [Hash])
    middleware.call({})

    assert_mock zen
    assert_mock app

    zen.expect :current_context, context
    app.expect(:call, [200, {}, ["OK"]], [Hash])
    middleware.call({})

    assert_mock zen
    assert_mock app

    zen.expect :current_context, context
    app.expect(:call, [200, {}, ["OK"]], [Hash])
    middleware.call({})

    assert_mock zen
    assert_mock app
  end
end
