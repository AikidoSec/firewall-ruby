# frozen_string_literal: true

require_relative "bucket"

module Aikido::Zen
  # @api private
  #
  # Circuit breaker that rate limits internal API requests in two ways: By using
  # a sliding window, to allow only a certain number of events over that window,
  # and with the ability of manually being tripped open when the API responds to
  # a request with a 429.
  class RateLimiter::Breaker
    def initialize(config: Aikido::Zen.config, clock: RateLimiter::Bucket::DEFAULT_CLOCK)
      @config = config
      @clock = clock

      @bucket = RateLimiter::Bucket.new(
        ttl: config.client_rate_limit_period,
        max_size: config.client_rate_limit_max_events,
        clock: clock
      )
      @opened_at = nil
    end

    # Trip the circuit open to force all events to be throttled until the
    # deadline passes.
    #
    # @see Aikido::Zen::Config#server_rate_limit_deadline
    # @return [void]
    def open!
      @opened_at = @clock.call
    end

    # @param event [#type] an event which we'll discriminate by type to decide
    #   if we should throttle it.
    # @return [Boolean]
    def throttle?(event)
      return true if open? && !try_close

      result = @bucket.increment(event.type)
      result.throttled?
    end

    # @!visibility private
    # @return [Boolean]
    def open?
      @opened_at
    end

    private

    def past_deadline?
      @opened_at < @clock.call - @config.server_rate_limit_deadline
    end

    def try_close
      @opened_at = nil if past_deadline?
      @opened_at.nil?
    end
  end
end
