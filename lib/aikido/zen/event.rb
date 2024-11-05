# frozen_string_literal: true

module Aikido::Zen
  # Base class for all events. You should be using one of the subclasses defined
  # in the Events module.
  class Event
    attr_reader :type
    attr_reader :time
    attr_reader :system_info

    def initialize(type:, system_info: Aikido::Zen.system_info, time: Time.now.utc)
      @type = type
      @time = time
      @system_info = system_info
    end

    def as_json
      {
        type: type,
        time: time.to_i * 1000,
        agent: system_info.as_json
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
      attr_reader :attack

      def initialize(attack:, **opts)
        @attack = attack
        super(type: "detected_attack", **opts)
      end

      def as_json
        super.update(
          attack: @attack.as_json,
          request: @attack.context.request.as_json
        )
      end
    end

    class Heartbeat < Event
      def initialize(stats:, users:, hosts:, routes:, **opts)
        super(type: "heartbeat", **opts)
        @stats = stats
        @users = users
        @hosts = hosts
        @routes = routes
      end

      def as_json
        super.update(
          stats: @stats.as_json,
          users: @users.as_json,
          routes: @routes.as_json,
          hostnames: @hosts.as_json
        )
      end
    end
  end
end
