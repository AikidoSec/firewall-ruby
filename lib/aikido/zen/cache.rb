# frozen_string_literal: true

module Aikido::Zen
  class Cache
    extend Forwardable

    # @api private
    # Visible for testing.
    def_delegators :@data,
      :size, :empty?

    def initialize(capacity, default_value = nil, ttl:, clock: nil)
      @default_value = default_value
      @ttl = ttl
      @clock = clock

      @data = CappedMap.new(capacity, mode: :lru)
    end

    def key?(key)
      @data.key?(key) && !@data[key].expired?
    end

    # @param key [Object] the key
    # @param value [Object] the value
    # @return [Object] the value that the key was set to
    def []=(key, value)
      if key?(key)
        entry = @data[key]
        entry.refresh
        entry.value = value
      else
        @data[key] = CacheEntry.new(value, ttl: @ttl, clock: @clock)
      end
    end

    def [](key)
      if key?(key)
        @data[key].value
      else
        @default_value
      end
    end

    def delete(key)
      if key?(key)
        @data.delete(key).value
      else
        @data.delete(key)
        nil
      end
    end

    # @api private
    # Visible for testing.
    def to_a
      @data.map { |key, entry| [key, entry.value] }
    end

    # @api private
    # Visible for testing.
    def to_h
      to_a.to_h
    end
  end

  class CacheEntry
    attr_accessor :value

    DEFAULT_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) }

    # @param value [Object] the value
    # @param ttl [Integer] the time-to-live in milliseconds
    # @return [Aikido::Zen::CacheEntry]
    def initialize(value, ttl:, clock: nil)
      @value = value
      @ttl = ttl
      @clock = clock || DEFAULT_CLOCK

      refresh
    end

    def refresh
      @expires = @clock.call + @ttl
    end

    def expired?
      @clock.call >= @expires
    end
  end
end
