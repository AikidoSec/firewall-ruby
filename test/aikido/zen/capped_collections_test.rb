# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::CappedCollectionsTest < ActiveSupport::TestCase
  class SetTest < ActiveSupport::TestCase
    test "an empty set" do
      set = Aikido::Zen::CappedSet.new(3)

      assert_equal 0, set.size
      assert set.empty?
      refute set.any?

      assert_equal Set.new, set.to_set
      assert_equal [], set.to_a
      assert_equal({}, set.to_h)
    end

    test "cannot create a 0-capacity set" do
      error = assert_raise ArgumentError do
        Aikido::Zen::CappedSet.new(0)
      end

      assert_match(/cannot set capacity lower than 1: 0/, error.message)
    end

    test "cannot create a negative-capacity set" do
      error = assert_raise ArgumentError do
        Aikido::Zen::CappedSet.new(-1)
      end

      assert_match(/cannot set capacity lower than 1: -1/, error.message)
    end

    test "is enumberable" do
      set = Aikido::Zen::CappedSet.new(3)
      assert_respond_to set, :each
      assert_kind_of Enumerable, set
    end

    test "adding items to the set works" do
      set = Aikido::Zen::CappedSet.new(3)
      set << 1 << 2 << 3

      assert_equal 3, set.size
      assert_includes set, 1
      assert_includes set, 2
      assert_includes set, 3
    end

    test "duplicates are ignored when adding" do
      set = Aikido::Zen::CappedSet.new(3)
      set << "x" << "x" << "x"

      assert_equal 1, set.size
      assert_includes set, "x"
    end

    test "duplicates don't care about insertion order" do
      set = Aikido::Zen::CappedSet.new(3)
      set << "x" << "x" << "x" << "y" << "x"

      assert_equal 2, set.size
      assert_equal ["x", "y"], set.to_a
    end

    test "overflowing the set removes the lead recently added element first" do
      set = Aikido::Zen::CappedSet.new(3)

      set << 1 << 2 << 3
      assert_equal [1, 2, 3], set.to_a

      set << 4
      assert_equal [2, 3, 4], set.to_a

      set << 1
      assert_equal [3, 4, 1], set.to_a
    end

    test "#as_json expects elements to respond to #as_json" do
      x = Object.new
      def x.as_json
        "x"
      end

      y = Object.new
      def y.as_json
        "y"
      end

      set = Aikido::Zen::CappedSet.new(3)
      set << x << y

      assert_equal ["x", "y"], set.as_json
    end

    test "#as_json fails if elements don't respond to #as_json" do
      x = NonSerializable.new(1)
      y = NonSerializable.new(2)

      set = Aikido::Zen::CappedSet.new(3)
      set << x << y

      assert_raises NoMethodError do
        set.as_json
      end
    end

    # Since ActiveSupport patches Object to respond to #as_json, we need an object
    # that can be added to a set but that does not implement #as_json.
    class NonSerializable < BasicObject
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def ==(other)
        value == other.value
      end
      alias_method :eql?, :==

      def hash
        value.hash
      end
    end
  end

  class MapTest < ActiveSupport::TestCase
    test "an empty map" do
      map = Aikido::Zen::CappedMap.new(3)

      assert_equal 0, map.size
      assert map.empty?
      refute map.any?

      assert_equal({}, map.to_hash)
      assert_equal [], map.to_a
    end

    test "cannot create a 0-capacity map" do
      error = assert_raise ArgumentError do
        Aikido::Zen::CappedMap.new(0)
      end

      assert_match(/cannot set capacity lower than 1: 0/, error.message)
    end

    test "cannot create a negative-capacity set" do
      error = assert_raise ArgumentError do
        Aikido::Zen::CappedMap.new(-1)
      end

      assert_match(/cannot set capacity lower than 1: -1/, error.message)
    end

    test "is enumberable" do
      map = Aikido::Zen::CappedMap.new(3)
      assert_respond_to map, :each
      assert_kind_of Enumerable, map
    end

    test "preserves hash semantics" do
      map = Aikido::Zen::CappedMap.new(3)

      map[1] = :a
      map[2] = :b
      map[3] = :c
      map[2] = :B

      assert_equal 3, map.size

      assert_equal :a, map[1]
      assert_equal :B, map[2]
      assert_equal :c, map[3]
      assert_nil map[4]

      assert_equal :a, map.fetch(1)
      assert_equal :B, map.fetch(2)
      assert_equal :c, map.fetch(3)
      assert_raise(KeyError) { map.fetch(4) }
      assert_nil map.fetch(4, nil)

      assert_equal :B, map.delete(2)
      assert_nil map[2]
      assert_raise(KeyError) { map.fetch(2) }
      assert_equal :b, map.fetch(2, :b)
    end

    test "insertion order is preserved" do
      map = Aikido::Zen::CappedMap.new(3)
      map[3] = :c
      map[2] = :b
      map[1] = :a
      map[2] = :B

      assert_equal 3, map.size
      assert_equal [[3, :c], [2, :B], [1, :a]], map.to_a
      assert_equal({3 => :c, 2 => :B, 1 => :a}, map.to_h)
    end

    test "overflowing the map removes the least recently added element first" do
      map = Aikido::Zen::CappedMap.new(3)

      map[1] = :a
      map[2] = :b
      map[3] = :c
      assert_equal [[1, :a], [2, :b], [3, :c]], map.to_a
      assert_equal({1 => :a, 2 => :b, 3 => :c}, map.to_h)

      map[4] = :d
      assert_equal [[2, :b], [3, :c], [4, :d]], map.to_a
      assert_equal({2 => :b, 3 => :c, 4 => :d}, map.to_h)

      map[3] = :C
      assert_equal [[2, :b], [3, :C], [4, :d]], map.to_a
      assert_equal({2 => :b, 3 => :C, 4 => :d}, map.to_h)

      map[1] = :a
      assert_equal [[3, :C], [4, :d], [1, :a]], map.to_a
      assert_equal({3 => :C, 4 => :d, 1 => :a}, map.to_h)
    end

    test "overflowing the map removes the least recently used element first in :lru mode" do
      map = Aikido::Zen::CappedMap.new(3, mode: :lru)

      map[1] = :a
      map[2] = :b
      map[3] = :c
      assert_equal [[1, :a], [2, :b], [3, :c]], map.to_a
      assert_equal({1 => :a, 2 => :b, 3 => :c}, map.to_h)

      map[4] = :d
      assert_equal [[2, :b], [3, :c], [4, :d]], map.to_a
      assert_equal({2 => :b, 3 => :c, 4 => :d}, map.to_h)

      map[3] = :C
      assert_equal [[2, :b], [3, :C], [4, :d]], map.to_a
      assert_equal({2 => :b, 3 => :C, 4 => :d}, map.to_h)

      # Simulate use map[2] so that map[3] and not map[2] is not removed next.
      map[2]

      # Simulate use map[3] so that map[4] and not map[3] is not removed next.
      map.fetch(3, nil)

      map[1] = :a
      assert_equal [[2, :b], [3, :C], [1, :a]], map.to_a
      assert_equal({2 => :b, 3 => :C, 1 => :a}, map.to_h)
    end

    test "default value from parameter" do
      map = Aikido::Zen::CappedMap.new(3, 123, mode: :lru)

      assert_equal 123, map[1]
      assert_equal 123, map[2]
      assert_equal 123, map[3]
      assert_equal 123, map[4]

      assert_equal [], map.to_a
    end

    test "default value returned from block" do
      map = Aikido::Zen::CappedMap.new(3, mode: :lru) { |m, k| 123 }

      assert_equal 123, map[1]
      assert_equal 123, map[2]
      assert_equal 123, map[3]
      assert_equal 123, map[4]

      assert_equal [], map.to_a
    end

    test "default value assigned in block" do
      map = Aikido::Zen::CappedMap.new(3, mode: :lru) { |m, k| m[k] = 123 }

      assert_equal 123, map[1]
      assert_equal 123, map[2]
      assert_equal 123, map[3]
      assert_equal 123, map[4]

      assert_equal [[1, 123], [2, 123], [3, 123], [4, 123]], map.to_a
    end
  end
end
