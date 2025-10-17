# frozen_string_literal: true

# dRB Front object that will work as a bridge communication between child & parent
# processes.
# Every method is called from the child but it runs in the parent process.
module Aikido::Zen::DetachedAgent
  class FrontObject
    def initialize(
      config: Aikido::Zen.config,
      runtime_settings: Aikido::Zen.runtime_settings,
      collector: Aikido::Zen.collector,
      rate_limiter: Aikido::Zen::RateLimiter.new
    )
      @config = config
      @runtime_settings = runtime_settings
      @collector = collector
      @rate_limiter = rate_limiter
    end

    RequestKind = Struct.new(:route, :schema, :ip, :actor)

    def send_heartbeat_to_parent_process(heartbeat)
      @collector.push_heartbeat(heartbeat)
    end

    def send_collector_events(events_data)
      events_data.each do |event_data|
        event = Aikido::Zen::Collector::Event.from_json(event_data)
        @collector.add_event(event)
      end
    end

    # Method called by child processes to get an up-to-date version of the
    # runtime_settings
    def updated_settings
      @runtime_settings
    end

    def calculate_rate_limits(route_data, ip, actor_data)
      actor = Aikido::Zen::Actor.from_json(actor_data)
      route = Aikido::Zen::Route.form_json(route_data)
      @rate_limiter.calculate_rate_limits(RequestKind.new(route, nil, ip, actor))
    end
  end
end
