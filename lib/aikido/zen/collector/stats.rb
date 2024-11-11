# frozen_string_literal: true

require_relative "../capped_collections"

module Aikido::Zen
  # @api private
  #
  # Tracks information about how the Aikido Agent is used in the app.
  class Collector::Stats
    # @!visibility private
    attr_reader :started_at, :ended_at, :requests, :aborted_requests, :sinks

    # @!visibility private
    attr_writer :ended_at

    def initialize(config = Aikido::Zen.config)
      super()
      @config = config
      @sinks = Hash.new { |h, k| h[k] = Collector::SinkStats.new(k, @config) }
      @started_at = @ended_at = nil
      @requests = 0
      @aborted_requests = 0
    end

    # @return [Boolean]
    def empty?
      @requests.zero? && @sinks.empty?
    end

    # @return [Boolean]
    def any?
      !empty?
    end

    # Track the timestamp we start tracking this series of stats.
    #
    # @param at [Time]
    # @return [self]
    def start(at = Time.now.utc)
      @started_at = at
      self
    end

    # Sets the end time for these stats block, freezes it to avoid any more
    # writing to them, and compresses the timing stats in anticipation of
    # sending these to the Aikido servers.
    #
    # @param at [Time] the time at which we're resetting, which is set as the
    #   ending time for the returned copy.
    # @return [self]
    def flush(at: Time.now.utc)
      # Make sure the timing stats are compressed before copying, since we
      # need these compressed when we serialize this for the API.
      @sinks.each_value { |sink| sink.compress_timings(at: at) }
      @ended_at = at
      freeze
    end

    # @return [self]
    def add_request
      @requests += 1
      self
    end

    # @param scan [Aikido::Zen::Scan]
    # @return [self]
    def add_scan(scan)
      stats = @sinks[scan.sink.name]
      stats.scans += 1
      stats.errors += 1 if scan.errors?
      stats.add_timing(scan.duration)
      self
    end

    # @param attack [Aikido::Zen::Attack]
    # @param being_blocked [Boolean] whether the Agent blocked the
    #   request where this Attack happened or not.
    # @return [self]
    def add_attack(attack, being_blocked:)
      stats = @sinks[attack.sink.name]
      stats.attacks += 1
      stats.blocked_attacks += 1 if being_blocked
      self
    end

    def as_json
      total_attacks, total_blocked = aggregate_attacks_from_sinks
      {
        startedAt: @started_at.to_i * 1000,
        endedAt: (@ended_at.to_i * 1000 if @ended_at),
        sinks: @sinks.transform_values(&:as_json),
        requests: {
          total: @requests,
          aborted: @aborted_requests,
          attacksDetected: {
            total: total_attacks,
            blocked: total_blocked
          }
        }
      }
    end

    private def aggregate_attacks_from_sinks
      @sinks.each_value.reduce([0, 0]) { |(attacks, blocked), stats|
        [attacks + stats.attacks, blocked + stats.blocked_attacks]
      }
    end
  end
end

require_relative "sink_stats"
