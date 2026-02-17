# frozen_string_literal: true

require_relative "../capped_collections"

module Aikido::Zen
  # @api private
  #
  # Tracks information about how the Aikido Agent is used in the app.
  class Collector::Stats
    # @!visibility private
    attr_reader :started_at, :ended_at, :requests, :aborted_requests, :user_agents, :attack_waves, :blocked_attack_waves, :sinks

    # @!visibility private
    attr_writer :ended_at

    def initialize(config = Aikido::Zen.config)
      super()
      @config = config

      @started_at = @ended_at = nil
      @requests = 0
      @aborted_requests = 0
      @user_agents = Hash.new { |h, k| h[k] = 0 }
      @attack_waves = 0
      @blocked_attack_waves = 0
      @sinks = Hash.new { |h, k| h[k] = Collector::SinkStats.new(k, @config) }
    end

    # @return [Boolean]
    def empty?
      @requests.zero? &&
        @user_agents.empty? &&
        @attack_waves.zero? &&
        @sinks.empty?
    end

    # @return [Boolean]
    def any?
      !empty?
    end

    # Track the timestamp we start tracking this series of stats.
    #
    # @param at [Time]
    # @return [void]
    def start(at = Time.now.utc)
      @started_at = at
    end

    # Sets the end time for these stats block, freezes it to avoid any more
    # writing to them, and compresses the timing stats in anticipation of
    # sending these to the Aikido servers.
    #
    # @param at [Time] the time at which we're resetting, which is set as the
    #   ending time for the returned copy.
    # @return [void]
    def flush(at: Time.now.utc)
      # Make sure the timing stats are compressed before copying, since we
      # need these compressed when we serialize this for the API.
      @sinks.each_value { |sink| sink.compress_timings(at: at) }
      @ended_at = at
      freeze
    end

    # @return [void]
    def add_request
      @requests += 1
    end

    # @param user_agent_keys [Array<String>] the user agent keys
    # @return [void]
    def add_user_agent(user_agent_keys)
      user_agent_keys&.each { |user_agent_key| @user_agents[user_agent_key] += 1 }
    end

    # @param being_blocked [Boolean] whether the Agent blocked the request
    # @return [void]
    def add_attack_wave(being_blocked:)
      @attack_waves += 1
      @blocked_attack_waves += 1 if being_blocked
    end

    # @param sink_name [String] the name of the sink
    # @param duration [Float] the length the scan in seconds
    # @param has_errors [Boolean] whether errors occurred during the scan
    # @return [void]
    def add_scan(sink_name, duration, has_errors:)
      stats = @sinks[sink_name]
      stats.scans += 1
      stats.errors += 1 if has_errors
      stats.add_timing(duration)
    end

    # @param sink_name [String] the name of the sink
    # @param being_blocked [Boolean] whether the Agent blocked the request
    # @return [void]
    def add_attack(sink_name, being_blocked:)
      stats = @sinks[sink_name]
      stats.attacks += 1
      stats.blocked_attacks += 1 if being_blocked
    end

    def as_json
      total_attacks, total_blocked = aggregate_attacks_from_sinks
      {
        startedAt: @started_at.to_i * 1000,
        endedAt: (@ended_at.to_i * 1000 if @ended_at),
        operations: @sinks.transform_values(&:as_json),
        requests: {
          total: @requests,
          aborted: @aborted_requests,
          rateLimited: 0,
          attacksDetected: {
            total: total_attacks,
            blocked: total_blocked
          },
          attackWaves: {
            total: @attack_waves,
            blocked: @blocked_attack_waves
          }
        },
        userAgents: {
          breakdown: @user_agents
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
