# frozen_string_literal: true

module RateLimitingAssertions
  def assert_throttled(result, **stats)
    assert result.throttled?
    assert_throttling_stats(result, **stats) if stats.any?
  end

  def refute_throttled(result, **stats)
    refute result.throttled?
    assert_throttling_stats(result, **stats) if stats.any?
  end

  def assert_throttling_stats(result, discriminator: nil, current: nil, time_remaining: nil)
    if discriminator
      assert_equal discriminator, result.discriminator,
        "expected request to be discriminated by #{discriminator}, got #{result.discriminator}"
    end

    if current
      assert_equal current, result.current_requests,
        "expected #{current} bucketed requests, got #{result.current_requests}"
    end

    if time_remaining
      assert_equal time_remaining, result.time_remaining,
        "expected #{time_remaining} seconds remaining, got #{result.time_remaining}"
    end
  end
end
