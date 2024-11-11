# frozen_string_literal: true

require_relative "../capped_collections"

module Aikido::Zen
  # @api private
  #
  # Tracks data specific to a single Sink.
  class Collector::SinkStats
    # @return [Integer] number of total calls to Sink#scan.
    attr_accessor :scans

    # @return [Integer] number of scans where our scanners raised an
    #   error that was handled.
    attr_accessor :errors

    # @return [Integer] number of scans where an attack was detected.
    attr_accessor :attacks

    # @return [Integer] number of scans where an attack was detected
    #   _and_ blocked by the Zen.
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
      @compressed_timings = CappedSet.new(@config.max_compressed_stats)
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
        compressedTimings: @compressed_timings.as_json
      }
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
  end
end
