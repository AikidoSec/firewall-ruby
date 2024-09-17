# frozen_string_literal: true

require_relative "../synchronizable"
require_relative "result"

module Aikido::Zen
  # This models a "sliding window" rate limiting bucket (where we keep a bucket
  # per endpoint). The timestamps of requests are kept grouped by client, and
  # when a new request is made, we check if the number of requests falls within
  # the configured limit.
  #
  # @example
  #   bucket = Aikido::Zen::RateLimiter::Bucket.new(ttl: 60, max_size: 3)
  #   bucket.increment("1.2.3.4") #=> true (count for this key: 1)
  #   bucket.increment("1.2.3.4") #=> true (count for this key: 2)
  #
  #   # 30 seconds go by
  #   bucket.increment("1.2.3.4") #=> true (count for this key: 3)
  #
  #   # 20 more seconds go by
  #   bucket.increment("1.2.3.4") #=> false (count for this key: 3)
  #
  #   # 20 more seconds go by
  #   bucket.increment("1.2.3.4") #=> true (count for this key: 2)
  #
  class RateLimiter::Bucket
    prepend Synchronizable

    # @!visibility private
    #
    # Use the monotonic clock to ensure time differences are consistent
    # and not affected by timezones.or daylight savings changes.
    DEFAULT_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC).round }

    def initialize(ttl:, max_size:, clock: DEFAULT_CLOCK)
      @ttl = ttl
      @max_size = max_size
      @data = Hash.new { |h, k| h[k] = [] }
      @clock = clock
    end

    # Increments the key if the number of entries within the current TTL window
    # is below the configured threshold.
    #
    # @param key [String] discriminating key to identify a client.
    #   See {Aikido::Zen::Config#rate_limiting_discriminator}.
    #
    # @return [Aikido::Zen::RateLimiter::Result] the result of the operation and
    #   statistics on this bucket for the given key.
    def increment(key)
      synchronize do
        time = @clock.call
        evict(key, at: time)

        entries = @data[key]
        throttled = entries.size >= @max_size

        entries << time unless throttled

        RateLimiter::Result.new(
          throttled: throttled,
          discriminator: key,
          current_requests: entries.size,
          max_requests: @max_size,
          time_remaining: @ttl - (time - entries.min)
        )
      end
    end

    private

    def evict(key, at: @clock.call)
      synchronize { @data[key].delete_if { |time| time < (at - @ttl) } }
    end
  end
end
