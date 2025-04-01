# frozen_string_literal: true

# dRB Front object that will work as a bridge communication between child & parent
# processes.
# Every method is called from the child but it runs in the parent process.
module Aikido::Zen::DetachedAgent
  class FrontObject
    def initialize(config: Aikido::Zen.config, collector: Aikido::Zen.collector)
      @config = config
    end

    def send_heartbeat_to_parent_process(heartbeat)
      pp "Received heartbeat: #{heartbeat} I'm running on #{Process.pid}"
    end
  end
end
