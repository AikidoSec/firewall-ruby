# frozen_string_literal: true

module Aikido::Agent
  # Base class for all events. You should be using one of the subclasses defined
  # in the Events module.
  class Event
    attr_reader :type
    attr_reader :time
    attr_reader :agent_info

    def initialize(type:, agent_info: Aikido::Agent.info, time: Time.now.utc)
      @type = type
      @time = time
      @agent_info = agent_info
    end

    def as_json
      {
        type: type,
        time: time.to_i * 1000,
        agent: agent_info.as_json
      }
    end
  end

  module Events
    # Event sent when starting up the agent.
    class Started < Event
      def initialize(**opts)
        super(type: "started", **opts)
      end
    end
  end
end
