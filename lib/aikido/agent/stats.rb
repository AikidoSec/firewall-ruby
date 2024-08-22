# frozen_string_literal: true

require "concurrent"

module Aikido::Agent
  # Tracks information about how the Aikido Agent is used in the app.
  class Stats < Concurrent::Synchronization::LockableObject
    # @!visibility private
    attr_reader :started_at, :requests, :aborted_requests, :sinks

    def initialize(config = Aikido::Agent.config)
      super()
      @config = config
      @sinks = Hash.new { |h, k| h[k] = SinkStats.new(k, config) }
      @started_at = nil
      @requests = 0
      @aborted_requests = 0
    end

    # @return [Boolean]
    def empty?
      synchronize { @requests.zero? && @sinks.empty? }
    end

    # @return [Boolean]
    def any?
      !empty?
    end

    # Track the timestamp we start tracking this series of stats.
    #
    # @return [void]
    def start(at = Time.now.utc)
      synchronize { @started_at = at }
    end

    # Atomically serializes the stats as JSON and resets them to start
    # collecting a new set of stats.
    #
    # @return [Hash] the result of #as_json
    def serialize_and_reset(as_of: Time.now.utc)
      synchronize {
        # Before flushing the stats into JSON we need to compress any
        # timing stats, as the JSON representation includes these but
        # not the raw measurements.
        @sinks.each_value(&:compress_timings)
        serialized = as_json(ended_at: as_of)

        # Reset all the internal state
        @sinks.clear
        @requests = 0
        @aborted_requests = 0
        start(as_of)

        serialized
      }
    end

    # @param context [Aikido::Agent::Context]
    # @return [void]
    def add_request(context)
      synchronize { @requests += 1 }
      self
    end

    # @param [Aikido::Firewall::Scan]
    # @return [void]
    def add_scan(scan)
      synchronize {
        stats = @sinks[scan.sink.name]
        stats.scans += 1
        stats.errors += 1 if scan.errors?
        stats.add_timing(scan.duration)
      }
      self
    end

    # @param attack [Aikido::Firewall::Attack]
    # @param being_blocked [Boolean] whether the Agent blocked the
    #   request where this Attack happened or not.
    #
    # @return [void]
    def add_attack(attack, being_blocked:)
      synchronize {
        stats = @sinks[attack.sink.name]
        stats.attacks += 1
        stats.blocked_attacks += 1 if being_blocked
      }
      self
    end

    def as_json(ended_at: Time.now.utc)
      total_attacks, total_blocked = aggregate_attacks_from_sinks
      {
        startedAt: @started_at.to_i * 1000,
        endedAt: ended_at.to_i * 1000,
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

    # @api private
    #
    # Tracks data specific to a single Sink.
    class SinkStats
      # @return [Integer] number of total calls to Sink#scan.
      attr_accessor :scans

      # @return [Integer] number of scans where our scanners raised an
      #   error that was handled.
      attr_accessor :errors

      # @return [Integer] number of scans where an attack was detected.
      attr_accessor :attacks

      # @return [Integer] number of scans where an attack was detected
      #   _and_ blocked by the Agent.
      attr_accessor :blocked_attacks

      # @return [Set<Float>] keeps the duration of individual scans. If
      #   this grows to match Config#max_performance_samples, the set is
      #   cleared and the data is aggregated into #compressed_timings.
      attr_accessor :timings

      # @return [Array<CompressedTiming>] list of aggregated stats.
      attr_accessor :compressed_timings

      def initialize(name, config)
        @name = name
        @config = config

        @scans = 0
        @errors = 0

        @attacks = 0
        @blocked_attacks = 0

        @timings = Set.new
        @compressed_timings = []
      end

      def add_timing(duration)
        compress_timings if @timings.size >= @config.max_performance_samples
        @timings << duration
      end

      def compress_timings(at: Time.now.utc)
        return if @timings.empty?

        list = @timings.sort
        @timings.clear

        mean = list.sum / list.size
        percentiles = percentiles(list, 50, 75, 90, 95, 99)

        discard_compressed_metrics if @compressed_timings.size >= @config.max_compressed_stats
        @compressed_timings << CompressedTiming.new(mean, percentiles, at)
      end

      def as_json
        {
          total: @scans,
          interceptorThrewError: @errors,
          withoutContext: 0,
          attacksDetected: {
            total: @attacks,
            blocked: @blocked_attacks
          },
          compressedTimings: @compressed_timings.map(&:as_json)
        }
      end

      private def discard_compressed_metrics
        message = format(
          DISCARD_LOG_MESSAGE,
          @compressed_timings.size,
          @compressed_timings.first.compressed_at.iso_8601
        )
        @logger.config.debug(message)
        @compressed_timings.shift
      end

      private def percentiles(sorted, *scores)
        return {} if sorted.empty? || scores.empty?

        scores.map { |p|
          index = (sorted.size * (p / 100.0)).floor
          [p, sorted.at(index)]
        }.to_h
      end

      CompressedTiming = Struct.new(:mean, :percentiles, :compressed_at) do
        def as_json
          {
            averageInMs: mean * 1000,
            percentiles: percentiles.transform_values { |t| t * 1000 },
            compressedAt: compressed_at.to_i * 1000
          }
        end
      end

      DISCARD_LOG_MESSAGE = "Discarding compressed timing data due to overflow (Size: %d, Timing data from: %s)"
    end
  end
end
