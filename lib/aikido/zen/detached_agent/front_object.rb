# frozen_string_literal: true

# dRB Front object that will be used to access the collector.
module Aikido::Zen::DetachedAgent
  class FrontObject
    extend Forwardable

    # Request, Sink & Scan-like structs to hold the minimal values to be sent to collector
    RequestKind = Struct.new(:route, :schema)
    SinkKind = Struct.new(:name)
    ScanKind = Struct.new(:sink, :errors, :duration) do
      def errors?
        self[:errors]
      end
    end
    AttackKind = Struct.new(:sink, :blocked) do
      def blocked?
        self[:blocked]
      end
    end

    def_delegators :@collector, :middleware_installed!, :track_request

    def initialize(config: Aikido::Zen.config, collector: Aikido::Zen.collector)
      @config = config
      @collector = collector
    end

    def track_route(route, schema)
      @collector.track_route(RequestKind.new(route, Aikido::Zen::Request::Schema.from_json(schema)))
    end

    def track_outbound(outbound)
      @collector.track_outbound(outbound)
    end

    def track_scan(sink_name, has_errors, duration)
      @collector.track_scan(ScanKind.new(SinkKind.new(sink_name), has_errors, duration))
    end

    def track_user(id, name, first_seen_at, ip)
      @collector.track_user(Actor.new(id: id, name: name, seen_at: first_seen_at, ip: ip))
    end

    def track_attack(sink_name, is_blocked)
      @collector.track_attack(AttackKind.new(SinkKind.new(sink_name), is_blocked))
    end
  end
end
