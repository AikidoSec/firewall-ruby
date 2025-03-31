# frozen_string_literal: true

# dRB Front object that will work as a bridge communication between child & parent
# processes.
# Every method is called from the child but it runs in the parent process.
module Aikido::Zen::DetachedAgent
  class FrontObject
    def initialize(
      config: Aikido::Zen.config, 
      collector: Aikido::Zen.collector,
      rate_limiter: Aikido::Zen::RateLimiter.new
    )
      @config = config
      @collector = collector
      @rate_limiter = rate_limiter
    end

    def send_heartbeat_to_parent_process(heartbeat)
      @collector.push_heartbeat(heartbeat)
    end

    def calculate_rate_limits(route, ip, actor_hash)
      actor = Aikido::Zen::Actor(actor_hash) if actor_hash
      @rate_limiter.calculate_rate_limits(RequestKind.new(route, nil, ip, actor))
    end
  end
end
