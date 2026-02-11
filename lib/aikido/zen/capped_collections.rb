# frozen_string_literal: true

require "forwardable"

module Aikido::Zen
  # @api private
  #
  # Provides a FIFO set with a maximum size. Adding an element after the
  # capacity has been reached kicks the oldest element in the set out,
  # while maintaining the uniqueness property of a set (relying on #eql?
  # and #hash).
  class CappedSet
    include Enumerable
    extend Forwardable

    def_delegators :@data, :size, :empty?

    # @return [Integer]
    attr_reader :capacity

    def initialize(capacity, mode: :fifo)
      @data = CappedMap.new(capacity, mode: mode)
    end

    def <<(element)
      @data[element] = nil
      self
    end
    alias_method :add, :<<
    alias_method :push, :<<

    def each(&b)
      @data.each_key(&b)
    end

    def as_json
      map(&:as_json)
    end
  end

  # @api private
  #
  # Provides a FIFO hash-like structure with a maximum size. Adding a new key
  # after the capacity has been reached kicks the first element pair added out.
  class CappedMap
    include Enumerable
    extend Forwardable

    def_delegators :@data,
      :delete, :key?,
      :each, :each_key, :each_value,
      :size, :empty?, :to_hash

    # @return [Integer]
    attr_reader :capacity

    def initialize(capacity, default_value = nil, mode: :fifo, &block)
      raise ArgumentError, "cannot set capacity lower than 1: #{capacity}" if capacity < 1

      unless [:fifo, :lru].include?(mode)
        raise ArgumentError, "unsupported mode: #{mode}"
      end

      @capacity = capacity
      @mode = mode

      @data = default_value ? Hash.new(default_value) : Hash.new(&block)
    end

    def []=(key, value)
      @data[key] = value
      @data.delete(@data.each_key.first) if @data.size > @capacity
    end

    def [](key)
      @data[key] = @data.delete(key) if @mode == :lru && key?(key)
      @data[key]
    end

    def fetch(key, ...)
      return self[key] if key?(key)

      @data.fetch(key, ...)
    end
  end
end
