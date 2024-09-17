# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RateLimiter::BreakerTest < ActiveSupport::TestCase
  setup do
    @config = Aikido::Zen.config
    @clock = TestClock.new
  end

  test "breaker allows events by default" do
    breaker = Aikido::Zen::RateLimiter::Breaker.new

    refute breaker.throttle?(stub_event)
  end

  test "breaker allows up to config.client_rate_limit_max_events events" do
    @config.client_rate_limit_period = 5
    @config.client_rate_limit_max_events = 2

    breaker = Aikido::Zen::RateLimiter::Breaker.new(config: @config)

    refute breaker.throttle?(stub_event(type: "test"))
    refute breaker.throttle?(stub_event(type: "test"))
    assert breaker.throttle?(stub_event(type: "test"))
  end

  test "breaker allows events after a sliding window of config.client_rate_limit_period seconds" do
    @config.client_rate_limit_period = 5
    @config.client_rate_limit_max_events = 2

    breaker = Aikido::Zen::RateLimiter::Breaker.new(config: @config, clock: @clock)

    refute breaker.throttle?(stub_event(type: "test"))

    @clock.advance(2)
    refute breaker.throttle?(stub_event(type: "test"))
    assert breaker.throttle?(stub_event(type: "test"))

    @clock.advance(4) # clears the first event
    refute breaker.throttle?(stub_event(type: "test"))
  end

  test "breaker discriminates by event type" do
    @config.client_rate_limit_max_events = 2

    breaker = Aikido::Zen::RateLimiter::Breaker.new(config: @config)
    refute breaker.throttle?(stub_event(type: "test"))
    refute breaker.throttle?(stub_event(type: "test"))
    assert breaker.throttle?(stub_event(type: "test"))

    refute breaker.throttle?(stub_event(type: "another"))
  end

  test "breaker rejects events after it's explicitly opened" do
    breaker = Aikido::Zen::RateLimiter::Breaker.new
    breaker.open!

    assert breaker.throttle?(stub_event(type: "test"))
  end

  test "breaker automatically closes after the deadline has passed" do
    breaker = Aikido::Zen::RateLimiter::Breaker.new(config: @config, clock: @clock)
    breaker.open!

    assert breaker.throttle?(stub_event(type: "test"))

    @clock.advance(@config.server_rate_limit_deadline + 1)
    refute breaker.throttle?(stub_event(type: "test"))
  end

  def stub_event(type: "test")
    Aikido::Zen::Event.new(type: type)
  end

  class TestClock
    def initialize(epoch: Time.now)
      @epoch = epoch
    end

    def advance(seconds = 1)
      @epoch += seconds
    end

    def call
      @epoch
    end
  end
end
