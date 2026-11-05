# frozen_string_literal: true

module Aikido::Zen
  # @api private
  #
  # Tracks information about how the Aikido Agent is used in the app.
  class Collector::Stats
    # @!visibility private
    attr_reader :started_at, :ended_at, :requests, :aborted_requests, :rate_limited_requests, :user_agents, :ip_lists, :attack_waves, :blocked_attack_waves, :sinks

    # @!visibility private
    attr_writer :ended_at

    def initialize
      @started_at = @ended_at = nil
      @requests = 0
      @aborted_requests = 0
      @rate_limited_requests = 0
      @user_agents = Hash.new { |h, k| h[k] = 0 }
      @ip_lists = Hash.new { |h, k| h[k] = 0 }
      @attack_waves = 0
      @blocked_attack_waves = 0
      @sinks = Hash.new { |h, k| h[k] = Collector::SinkStats.new(k) }
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
    # writing to them.
    #
    # @param at [Time] the time at which we're resetting, which is set as the
    #   ending time for the returned copy.
    # @return [void]
    def flush(at: Time.now.utc)
      @ended_at = at
      freeze
    end

    # @return [void]
    def add_request
      @requests += 1
    end

    # @return [void]
    def add_rate_limited_request
      @rate_limited_requests += 1
    end

    # @param user_agent_keys [Array<String>] the user agent keys
    # @return [void]
    def add_user_agent(user_agent_keys)
      user_agent_keys&.each { |user_agent_key| @user_agents[user_agent_key] += 1 }
    end

    # @param user_agent_keys [Array<String>] the user agent keys
    # @return [void]
    def add_ip_list(ip_list_keys)
      ip_list_keys&.each { |ip_list_key| @ip_lists[ip_list_key] += 1 }
    end

    # @param being_blocked [Boolean] whether the Agent blocked the request
    # @return [void]
    def add_attack_wave(being_blocked:)
      @attack_waves += 1
      @blocked_attack_waves += 1 if being_blocked
    end

    # @param sink_name [String] the name of the sink
    # @param sink_kind [String] the category of operation the sink represents
    # @param has_errors [Boolean] whether errors occurred during the scan
    # @return [void]
    def add_scan(sink_name, sink_kind, has_errors:)
      stats = @sinks[sink_name]
      stats.kind = sink_kind
      stats.scans += 1
      stats.errors += 1 if has_errors
    end

    # @param sink_name [String] the name of the sink
    # @param sink_kind [String] the category of operation the sink represents
    # @param being_blocked [Boolean] whether the Agent blocked the request
    # @return [void]
    def add_attack(sink_name, sink_kind, being_blocked:)
      stats = @sinks[sink_name]
      stats.kind = sink_kind
      stats.attacks += 1
      stats.blocked_attacks += 1 if being_blocked
    end

    def as_json
      total_attacks, total_blocked = aggregate_attacks_from_sinks
      {
        "startedAt" => @started_at.to_i * 1000,
        "endedAt" => (@ended_at.to_i * 1000 if @ended_at),
        "operations" => @sinks.transform_values(&:as_json),
        "requests" => {
          "total" => @requests,
          "aborted" => @aborted_requests,
          "rateLimited" => @rate_limited_requests,
          "attacksDetected" => {
            "total" => total_attacks,
            "blocked" => total_blocked
          },
          "attackWaves" => {
            "total" => @attack_waves,
            "blocked" => @blocked_attack_waves
          }
        },
        "userAgents" => {
          "breakdown" => @user_agents
        },
        "ipAddresses" => {
          "breakdown" => @ip_lists
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
