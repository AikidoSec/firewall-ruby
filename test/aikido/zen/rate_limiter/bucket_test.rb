# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RateLimiter::BucketTest < ActiveSupport::TestCase
  include RateLimitingAssertions

  Bucket = Aikido::Zen::RateLimiter::Bucket

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

  setup do
    @clock = TestClock.new
  end

  test "#increment returns a Result" do
    bucket = Bucket.new(ttl: 5, max_size: 3)

    assert_kind_of Aikido::Zen::RateLimiter::Result, bucket.increment("key")
  end

  test "#increment returns whether the count for the key was incremented" do
    bucket = Bucket.new(ttl: 5, max_size: 3, clock: @clock)

    refute_throttled bucket.increment("key"), current: 1, time_remaining: 5
    @clock.advance
    refute_throttled bucket.increment("key"), current: 2, time_remaining: 4
    @clock.advance
    refute_throttled bucket.increment("key"), current: 3, time_remaining: 3

    assert_throttled bucket.increment("key"), current: 3, time_remaining: 3

    @clock.advance(4)
    refute_throttled bucket.increment("key"), current: 3, time_remaining: 0
  end

  test "different keys are independent of each other" do
    bucket = Bucket.new(ttl: 5, max_size: 3, clock: @clock)

    refute_throttled bucket.increment("key"), current: 1
    refute_throttled bucket.increment("key"), current: 2

    refute_throttled bucket.increment("another_key"), current: 1
    refute_throttled bucket.increment("another_key"), current: 2
  end

  test "stale entries are evicted automatically when calling #increment" do
    bucket = Bucket.new(ttl: 2, max_size: 3, clock: @clock)

    t0 = @clock.call

    refute_throttled bucket.increment("key")
    assert_equal [t0], raw_entries(bucket, "key")

    @clock.advance
    refute_throttled bucket.increment("key")
    assert_equal [t0, t0 + 1], raw_entries(bucket, "key")

    @clock.advance
    refute_throttled bucket.increment("key")
    assert_equal [t0, t0 + 1, t0 + 2], raw_entries(bucket, "key")

    @clock.advance
    refute_throttled bucket.increment("key")
    assert_equal [t0 + 1, t0 + 2, t0 + 3], raw_entries(bucket, "key")
  end

  def raw_entries(bucket, key)
    bucket.instance_variable_get(:@data)[key]
  end
end
