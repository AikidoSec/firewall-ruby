# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::CacheTest < ActiveSupport::TestCase
  class TestClock
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

  class CacheTest < ActiveSupport::TestCase
    def build_cache(capacity = 3, ttl: 1000, &blk)
      Aikido::Zen::Cache.new(capacity, ttl: ttl, clock: @clock, &blk)
    end

    setup do
      @clock = TestClock.new
    end

    test "can create cache" do
      cache = build_cache(3)

      refute_nil cache

      assert_equal 0, cache.size
      assert cache.empty?
      assert_equal({}, cache.to_h)
    end

    test "cannot create a 0-capacity cache" do
      error = assert_raise ArgumentError do
        build_cache(0)
      end

      assert_match(/cannot set capacity lower than 1: 0/, error.message)
    end

    test "cannot create a negative-capacity cache" do
      error = assert_raise ArgumentError do
        build_cache(-1)
      end

      assert_match(/cannot set capacity lower than 1: -1/, error.message)
    end

    test "can insert values" do
      cache = build_cache(3)

      cache["a"] = 1
      cache["b"] = 2
      cache["c"] = 3
      cache["b"] = -2

      assert_equal 3, cache.size

      assert_equal 1, cache["a"]
      assert_equal(-2, cache["b"])
      assert_equal 3, cache["c"]
      assert_nil cache["d"]
    end

    test "can delete values" do
      cache = build_cache(3)

      cache["a"] = 1
      cache["b"] = 2
      cache["c"] = 3
      cache["b"] = -2

      assert_equal 3, cache.size

      assert_equal 1, cache["a"]
      assert_equal(-2, cache["b"])
      assert_equal 3, cache["c"]
      assert_nil cache["d"]

      assert_equal 1, cache.delete("a")
      assert_nil cache[1]
      assert_equal(-2, cache.delete("b"))
      assert_nil cache[2]
      assert_equal 3, cache.delete("c")
      assert_nil cache[3]
      assert_nil cache.delete(4)

      assert cache.empty?
    end

    test "insertion order is preserved" do
      cache = build_cache(3)

      cache["c"] = 3
      cache["b"] = 2
      cache["a"] = 1
      cache["b"] = -2

      assert_equal 3, cache.size

      assert_equal [["c", 3], ["a", 1], ["b", -2]], cache.to_a
      assert_equal({"c" => 3, "a" => 1, "b" => -2}, cache.to_h)
    end

    test "values expire after the time-to-live" do
      cache = build_cache(3, ttl: 5000)

      cache["a"] = 1
      assert cache.key?("a")
      @clock.advance(1000)
      cache["b"] = 2
      assert cache.key?("b")
      @clock.advance(2000)
      cache["c"] = 3
      assert cache.key?("c")
      refute cache.key?("d")
      assert_nil cache["d"]

      assert cache.key?("a")
      @clock.advance(1000)
      assert cache.key?("a")
      @clock.advance(1000)
      refute cache.key?("a")
      assert_nil cache["a"]

      assert cache.key?("b")
      @clock.advance(1000)
      refute cache.key?("b")
      assert_nil cache["b"]

      assert cache.key?("c")
      @clock.advance(2000)
      refute cache.key?("c")
      assert_nil cache["c"]
    end

    test "default value returned from block" do
      cache = build_cache(7, ttl: 5000) { Aikido::Zen::CappedSet.new(5) }

      value = cache["a"]

      assert_kind_of Aikido::Zen::CappedSet, value
      assert_empty value

      cache["a"] <<= 1
      cache["a"] <<= 1
      cache["b"] <<= 2
      cache["b"] <<= 3
      cache["c"] <<= 3
      cache["c"] <<= 4
      cache["c"] <<= 5

      assert_equal 1, cache["a"].size
      assert_equal 2, cache["b"].size
      assert_equal 3, cache["c"].size
      assert_empty cache["d"]
    end
  end

  class CacheEntryTest < ActiveSupport::TestCase
    def build_cache_entry(value, ttl: 1000)
      Aikido::Zen::CacheEntry.new(value, ttl: ttl, clock: @clock)
    end

    setup do
      @clock = TestClock.new
    end

    test "can create cache entry" do
      entry = build_cache_entry(1)

      refute_nil entry

      refute entry.expired?
      assert_equal 1, entry.value
    end

    test "can set value" do
      entry = build_cache_entry(1)

      assert_equal 1, entry.value

      entry.value = 3

      assert_equal 3, entry.value
    end

    test "value expires after the time-to-live" do
      entry = build_cache_entry(3, ttl: 5000)

      assert_equal 3, entry.value

      refute entry.expired?
      @clock.advance(1000)
      refute entry.expired?
      @clock.advance(4000)
      assert entry.expired?

      assert_equal 3, entry.value
    end
  end
end
