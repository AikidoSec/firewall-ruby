# frozen_string_literal: true

module Aikido::Zen
  # Handles collecting all the runtime statistics to report back to the Aikido
  # servers.
  class Collector
    def initialize(config: Aikido::Zen.config)
      @config = config

      @stats = Concurrent::AtomicReference.new(Stats.new(@config))
      @users = Concurrent::AtomicReference.new(Users.new(@config))
      @hosts = Concurrent::AtomicReference.new(Hosts.new(@config))
      @routes = Concurrent::AtomicReference.new(Routes.new(@config))
    end

    # Flush all the stats into a Heartbeat event that can be reported back to
    # the Aikido servers.
    #
    # @param at [Time] the time at which stats collection stopped and the start
    #   of the new stats collection period. Defaults to now.
    # @return [Aikido::Zen::Events::Heartbeat]
    def flush(at: Time.now.utc)
      stats = @stats.get_and_set(Stats.new(@config))
      users = @users.get_and_set(Users.new(@config))
      hosts = @hosts.get_and_set(Hosts.new(@config))
      routes = @routes.get_and_set(Routes.new(@config))

      start(at: at)
      stats = stats.flush(at: at)

      Events::Heartbeat.new(stats: stats, users: users, hosts: hosts, routes: routes)
    end

    # Sets the start time for this collection period.
    #
    # @param at [Time] defaults to now.
    # @return [void]
    def start(at: Time.now.utc)
      synchronize(@stats) { |stats| stats.start(at) }
    end

    # Track stats about the request, record the visited endpoint, and if
    # enabled, the API schema for this endpoint.
    #
    # @param request [Aikido::Zen::Request]
    # @return [void]
    def track_request(request)
      synchronize(@stats) { |stats| stats.add_request }
      synchronize(@routes) { |routes| routes.add(request) if request.route }
    end

    # Track stats about a scan performed by one of our sinks.
    #
    # @param scan [Aikido::Zen::Scan]
    # @return [void]
    def track_scan(scan)
      synchronize(@stats) { |stats| stats.add_scan(scan) }
    end

    # Track stats about an attack detected by our scanners.
    #
    # @param attack [Aikido::Zen::Attack]
    # @return [void]
    def track_attack(attack)
      synchronize(@stats) do |stats|
        stats.add_attack(attack, being_blocked: attack.blocked?)
      end
    end

    # Track an HTTP connections to an external host.
    #
    # @param connection [Aikido::Zen::OutboundConnection]
    # @return [void]
    def track_outbound(connection)
      synchronize(@hosts) { |hosts| hosts.add(connection) }
    end

    # Track the user reported by the developer to be behind this request.
    #
    # @param actor [Aikido::Zen::Actor]
    # @return [void]
    def track_user(actor)
      synchronize(@users) { |users| users.add(actor) }
    end

    # @api private
    def routes
      @routes.get
    end

    # @api private
    def users
      @users.get
    end

    # @api private
    def hosts
      @hosts.get
    end

    # @api private
    def stats
      @stats.get
    end

    # Atomically modify an object's state within a block, ensuring it's safe
    # from other threads.
    private def synchronize(object)
      object.update { |obj| obj.tap { yield obj } }
    end
  end
end

require_relative "collector/stats"
require_relative "collector/users"
require_relative "collector/hosts"
require_relative "collector/routes"
