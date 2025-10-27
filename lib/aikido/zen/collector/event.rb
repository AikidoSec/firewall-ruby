# frozen_string_literal: true

module Aikido::Zen
  class Collector
    class Event
      @@registry = {}

      # @api protected
      def self.register(type)
        const_set(:TYPE, type)
        @@registry[type] = self
      end

      def self.from_json(data)
        type = data[:type]
        subclass = @@registry[type]
        subclass.from_json(data)
      end

      attr_reader :type

      def initialize
        @type = self.class::TYPE
      end

      def as_json
        {
          type: @type
        }
      end

      def handle(collector)
        raise NotImplementedError, "implement in subclasses"
      end
    end

    # @api private
    module Events
      class TrackRequest < Event
        register "track_request"

        def self.from_json(data)
          new
        end

        def handle(collector)
          collector.handle_track_request
        end

        def inspect
          "#<#{self.class.name}>"
        end
      end

      class TrackScan < Event
        register "track_scan"

        def self.from_json(data)
          new(
            data[:sink_name],
            data[:duration],
            has_errors: data[:has_errors]
          )
        end

        def initialize(sink_name, duration, has_errors:)
          super()
          @sink_name = sink_name
          @duration = duration
          @has_errors = has_errors
        end

        def as_json
          super.update({
            sink_name: @sink_name,
            duration: @duration,
            has_errors: @has_errors
          })
        end

        def handle(collector)
          collector.handle_track_scan(@sink_name, @duration, has_errors: @has_errors)
        end

        def inspect
          "#<#{self.class.name} #{@sink_name} #{format "%0.6f", @duration} #{@has_errors}>"
        end
      end

      class TrackAttack < Event
        register "track_attack"

        def self.from_json(data)
          new(
            data[:sink_name],
            being_blocked: data[:being_blocked]
          )
        end

        def initialize(sink_name, being_blocked:)
          super()
          @sink_name = sink_name
          @being_blocked = being_blocked
        end

        def as_json
          super.update({
            sink_name: @sink_name,
            being_blocked: @being_blocked
          })
        end

        def handle(collector)
          collector.handle_track_attack(@sink_name, being_blocked: @being_blocked)
        end

        def inspect
          "#<#{self.class.name} #{@sink_name} #{@being_blocked}>"
        end
      end

      class TrackUser < Event
        register "track_user"

        def self.from_json(data)
          new(Aikido::Zen::Actor.from_json(data[:actor]))
        end

        def initialize(actor)
          super()
          @actor = actor
        end

        def as_json
          super.update({
            actor: @actor.as_json
          })
        end

        def handle(collector)
          collector.handle_track_user(@actor)
        end

        def inspect
          "#<#{self.class.name} #{@actor.id} #{actor.name}>"
        end
      end

      class TrackOutbound < Event
        register "track_outbound"

        def self.from_json(data)
          new(OutboundConnection.from_json(data[:connection]))
        end

        def initialize(connection)
          super()
          @connection = connection
        end

        def as_json
          super.update({
            connection: @connection.as_json
          })
        end

        def handle(collector)
          collector.handle_track_outbound(@connection)
        end

        def inspect
          "#<#{self.class.name} #{@connection.host}:#{@connection.port}>"
        end
      end

      class TrackRoute < Event
        register "track_route"

        def self.from_json(data)
          new(
            Route.from_json(data[:route]),
            Request::Schema.from_json(data[:schema])
          )
        end

        def initialize(route, schema)
          super()
          @route = route
          @schema = schema
        end

        def as_json
          super.update({
            route: @route.as_json,
            schema: @schema.as_json
          })
        end

        def handle(collector)
          collector.handle_track_route(@route, @schema)
        end

        def inspect
          "#<#{self.class.name} #{@route.verb} #{@route.path.inspect}>"
        end
      end
    end
  end
end
