# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::CappedSetTest < ActiveSupport::TestCase
  test "an empty set" do
    set = Aikido::Agent::CappedSet.new(3)

    assert_equal 0, set.size
    assert set.empty?
    refute set.any?

    assert_equal Set.new, set.to_set
    assert_equal [], set.to_a
    assert_equal({}, set.to_h)
  end

  test "cannot create a 0-capacity set" do
    error = assert_raise ArgumentError do
      Aikido::Agent::CappedSet.new(0)
    end

    assert_match(/cannot set capacity lower than 1: 0/, error.message)
  end

  test "cannot create a negative-capacity set" do
    error = assert_raise ArgumentError do
      Aikido::Agent::CappedSet.new(-1)
    end

    assert_match(/cannot set capacity lower than 1: -1/, error.message)
  end

  test "is enumberable" do
    set = Aikido::Agent::CappedSet.new(3)
    assert_respond_to set, :each
    assert_kind_of Enumerable, set
  end

  test "adding items to the set works" do
    set = Aikido::Agent::CappedSet.new(3)
    set << 1 << 2 << 3

    assert_equal 3, set.size
    assert_includes set, 1
    assert_includes set, 2
    assert_includes set, 3
  end

  test "duplicates are ignored when adding" do
    set = Aikido::Agent::CappedSet.new(3)
    set << "x" << "x" << "x"

    assert_equal 1, set.size
    assert_includes set, "x"
  end

  test "duplicates don't care about insertion order" do
    set = Aikido::Agent::CappedSet.new(3)
    set << "x" << "x" << "x" << "y" << "x"

    assert_equal 2, set.size
    assert_equal ["x", "y"], set.to_a
  end

  test "overflowing the set removes the oldest element first" do
    set = Aikido::Agent::CappedSet.new(3)

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

    set = Aikido::Agent::CappedSet.new(3)
    set << x << y

    assert_equal ["x", "y"], set.as_json
  end

  test "#as_json fails if elements don't respond to #as_json" do
    x = NonSerializable.new(1)
    y = NonSerializable.new(2)

    set = Aikido::Agent::CappedSet.new(3)
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
