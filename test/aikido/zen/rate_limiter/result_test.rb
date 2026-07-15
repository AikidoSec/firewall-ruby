# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RateLimiter::ResultTest < ActiveSupport::TestCase
  setup do
    @result = Aikido::Zen::RateLimiter::Result.new(
      throttled: true,
      discriminator: "1.2.3.4",
      current_requests: 5,
      max_requests: 10,
      time_remaining: 30
    )
  end

  test "#as_json serializes all fields" do
    assert_equal({
      "throttled" => true,
      "discriminator" => "1.2.3.4",
      "current_requests" => 5,
      "max_requests" => 10,
      "time_remaining" => 30
    }, @result.as_json)
  end

  test ".from_json deserializes all fields" do
    data = {
      "throttled" => true,
      "discriminator" => "1.2.3.4",
      "current_requests" => 5,
      "max_requests" => 10,
      "time_remaining" => 30
    }

    result = Aikido::Zen::RateLimiter::Result.from_json(data)

    assert result.throttled?
    assert_equal "1.2.3.4", result.discriminator
    assert_equal 5, result.current_requests
    assert_equal 10, result.max_requests
    assert_equal 30, result.time_remaining
  end

  test "#as_json and #from_json round-trip" do
    result = Aikido::Zen::RateLimiter::Result.from_json(@result.as_json)

    assert_equal @result.throttled?, result.throttled?
    assert_equal @result.discriminator, result.discriminator
    assert_equal @result.current_requests, result.current_requests
    assert_equal @result.max_requests, result.max_requests
    assert_equal @result.time_remaining, result.time_remaining
  end
end
