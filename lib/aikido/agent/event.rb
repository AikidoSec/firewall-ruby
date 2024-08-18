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

    class Attack < Event
      def initialize(attack:, **opts)
        @attack = attack
        super(type: "detected_attack", **opts)
      end

      def as_json
        super.update(
          attack: @attack.as_json,
          request: @attack.request.as_json
        )
      end
    end

    class Heartbeat < Event
      def initialize(serialized_stats:, **opts)
        @serialized_stats = serialized_stats
        super(type: "heartbeat", **opts)
      end

      def as_json
        super.update(
          stats: @serialized_stats,
          hostnames: [],
          routes: [],
          users: []
        )
      end
    end
  end
end
