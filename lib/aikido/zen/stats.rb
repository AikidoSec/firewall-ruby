# frozen_string_literal: true

require "concurrent"

require_relative "capped_collections"

module Aikido::Zen
  # Tracks information about how the Aikido Agent is used in the app.
  class Stats < Concurrent::Synchronization::LockableObject
    # @!visibility private
    attr_reader :started_at, :ended_at, :requests, :aborted_requests, :sinks

    # @!visibility private
    attr_writer :ended_at

    def initialize(config = Aikido::Zen.config)
      super()
      @config = config
      reset_state
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

    # Atomically copies the stats and resets them to their initial values, so
    # you can start gathering a new set while being able to read the old ones
    # without fear that a thread might modify them.
    #
    # @param at [Time] the time at which we're resetting, which is set as the
    #   ending time for the returned copy.
    #
    # @return [Aikido::Zen::Stats] a frozen copy of the object before
    #   resetting, so you can access the data there, with its +ended_at+
    #   set to the given timestamp.
    def reset(at: Time.now.utc)
      synchronize {
        # Make sure the timing stats are compressed before copying, since we
        # need these compressed when we serialize this for the API.
        @sinks.each_value(&:compress_timings)

        copy = clone
        copy.ended_at = at

        reset_state
        start(at)

        copy
      }
    end

    # @param request [Aikido::Zen::Request]
    # @return [void]
    def add_request(request)
      synchronize {
        @requests += 1
        @routes.add(request.route, request.schema)
      }
      self
    end

    # @param connection [Aikido::Zen::OutboundConnection]
    # @return [void]
    def add_outbound(connection)
      synchronize { @outbound_connections << connection }
      self
    end

    # @param [Aikido::Zen::Scan]
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

    # @param attack [Aikido::Zen::Attack]
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

    # @param actor [Aikido::Zen::Actor]
    # @return [void]
    def add_user(actor)
      synchronize { @users.add(actor) }
    end

    # @return [#as_json] the set of routes visited during this stats-gathering
    #   period.
    def routes
      synchronize { @routes }
    end

    # @return [Enumerable<#as_json>] the set of users that had an active session
    #   during this stats-gathering period.
    def users
      synchronize { @users }
    end

    # @return [#as_json] the set of connections to outbound hosts that were
    #   established during this stats-gathering period.
    def outbound_connections
      synchronize { @outbound_connections }
    end

    def as_json
      synchronize {
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
      }
    end

    private def reset_state
      @sinks = Hash.new { |h, k| h[k] = SinkStats.new(k, @config) }
      @started_at = @ended_at = nil
      @requests = 0
      @routes = Routes.new
      @users = Users.new(@config.max_users_tracked)
      @outbound_connections = CappedSet.new(@config.max_outbound_connections)
      @aborted_requests = 0
    end

    private def aggregate_attacks_from_sinks
      @sinks.each_value.reduce([0, 0]) { |(attacks, blocked), stats|
        [attacks + stats.attacks, blocked + stats.blocked_attacks]
      }
    end
  end
end

require_relative "stats/users"
require_relative "stats/routes"
require_relative "stats/sink_stats"
