# frozen_string_literal: true

require_relative "collector/event"

module Aikido::Zen
  # Handles collecting all the runtime statistics to report back to the Aikido
  # servers.
  class Collector
    def initialize(config: Aikido::Zen.config)
      @config = config

      @events = Queue.new

      @stats = Concurrent::AtomicReference.new(Stats.new(@config))
      @users = Concurrent::AtomicReference.new(Users.new(@config))
      @hosts = Concurrent::AtomicReference.new(Hosts.new(@config))
      @routes = Concurrent::AtomicReference.new(Routes.new(@config))

      @middleware_installed = Concurrent::AtomicBoolean.new
    end

    # Add an event, to be handled in the collector in current process or sent
    # to a collector in another process.
    #
    # @param event [Aikido::Zen::Collector::Event] the event to add
    # @return [void]
    def add_event(event)
      @events << event
    end

    # @return [Boolean] whether the collector has any events
    def has_events?
      !@events.empty?
    end

    # Flush all events.
    #
    # @return [Array<Aikido::Zen::Collector::Event>]
    def flush_events
      Array.new(@events.size) { @events.pop }
    end

    # Handle the events in the queue.
    #
    # @return [void]
    def handle
      flush_events.each { |event| event.handle(self) }
    end

    # Flush all the stats into a Heartbeat event that can be reported back to
    # the Aikido servers.
    #
    # @param at [Time] the time at which stats collection stopped and the start
    #   of the new stats collection period. Defaults to now.
    # @return [Aikido::Zen::Events::Heartbeat]
    def flush(at: Time.now.utc)
      handle

      stats = @stats.get_and_set(Stats.new(@config))
      users = @users.get_and_set(Users.new(@config))
      hosts = @hosts.get_and_set(Hosts.new(@config))
      routes = @routes.get_and_set(Routes.new(@config))

      start(at: at)
      stats = stats.flush(at: at)

      Aikido::Zen::Events::Heartbeat.new(
        stats: stats, users: users, hosts: hosts, routes: routes, middleware_installed: middleware_installed?
      )
    end

    # Sets the start time for this collection period.
    #
    # @param at [Time] defaults to now.
    # @return [void]
    def start(at: Time.now.utc)
      synchronize(@stats) { |stats| stats.start(at) }
    end

    # Track stats about the requests
    #
    # @return [void]
    def track_request
      add_event(Events::TrackRequest.new)
    end

    def handle_track_request
      synchronize(@stats) { |stats| stats.add_request }
    end

    # Track stats about an attack detected by our scanners.
    #
    # @param attack [Aikido::Zen::Events::AttackWave]
    # @return [void]
    def track_attack_wave(being_blocked:)
      add_event(Events::TrackAttackWave.new(being_blocked: being_blocked))
    end

    def handle_track_attack_wave(being_blocked:)
      synchronize(@stats) do |stats|
        stats.add_attack_wave(being_blocked: being_blocked)
      end
    end

    # Track stats about a scan performed by one of our sinks.
    #
    # @param scan [Aikido::Zen::Scan]
    # @return [void]
    def track_scan(scan)
      add_event(Events::TrackScan.new(scan.sink.name, scan.duration, has_errors: scan.errors?))
    end

    def handle_track_scan(sink_name, duration, has_errors:)
      synchronize(@stats) do |stats|
        stats.add_scan(sink_name, duration, has_errors: has_errors)
      end
    end

    # Track stats about an attack detected by our scanners.
    #
    # @param attack [Aikido::Zen::Attack]
    # @return [void]
    def track_attack(attack)
      add_event(Events::TrackAttack.new(attack.sink.name, being_blocked: attack.blocked?))
    end

    def handle_track_attack(sink_name, being_blocked:)
      synchronize(@stats) do |stats|
        stats.add_attack(sink_name, being_blocked: being_blocked)
      end
    end

    # Track the user reported by the developer to be behind this request.
    #
    # @param actor [Aikido::Zen::Actor]
    # @return [void]
    def track_user(actor)
      add_event(Events::TrackUser.new(actor))
    end

    def handle_track_user(actor)
      synchronize(@users) { |users| users.add(actor) }
    end

    # Track an HTTP connections to an external host.
    #
    # @param connection [Aikido::Zen::OutboundConnection]
    # @return [void]
    def track_outbound(connection)
      add_event(Events::TrackOutbound.new(connection))
    end

    def handle_track_outbound(connection)
      synchronize(@hosts) { |hosts| hosts.add(connection) }
    end

    # Record the visited endpoint, and if enabled, the API schema for this endpoint.
    #
    # @param request [Aikido::Zen::Request]
    # @return [void]
    def track_route(request)
      add_event(Events::TrackRoute.new(request.route, request.schema))
    end

    def handle_track_route(route, schema)
      synchronize(@routes) { |routes| routes.add(route, schema) }
    end

    def middleware_installed!
      @middleware_installed.make_true
    end

    # @api private
    #
    # @note Visible for testing.
    def stats
      handle
      @stats.get
    end

    # @api private
    #
    # @note Visible for testing.
    def users
      handle
      @users.get
    end

    # @api private
    #
    # @note Visible for testing.
    def hosts
      handle
      @hosts.get
    end

    # @api private
    #
    # @note Visible for testing.
    def routes
      handle
      @routes.get
    end

    # @api private
    #
    # @note Visible for testing.
    def middleware_installed?
      @middleware_installed.true?
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
