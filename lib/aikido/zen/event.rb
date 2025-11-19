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
          {
            attack: @attack.as_json,
            request: @attack.context&.request&.as_json
          }.compact
        )
      end
    end

    class Heartbeat < Event
      def initialize(stats:, users:, hosts:, routes:, middleware_installed:, **opts)
        super(type: "heartbeat", **opts)
        @stats = stats
        @users = users
        @hosts = hosts
        @routes = routes
        @middleware_installed = middleware_installed
      end

      def as_json
        super.update(
          stats: @stats.as_json,
          users: @users.as_json,
          routes: @routes.as_json,
          hostnames: @hosts.as_json,
          middlewareInstalled: @middleware_installed
        )
      end
    end

    class AttackWave < Event
      # @param [Aikido::Zen::Context] a context
      # @return [Aikido::Zen::Events::AttackWave] an attack wave event
      def self.from_context(context)
        request = Aikido::Zen::AttackWave::Request.new(
          ip_address: context.request.client_ip,
          user_agent: context.request.user_agent,
          source: context.request.framework
        )

        attack = Aikido::Zen::AttackWave::Attack.new(
          metadata: {}, # not used yet
          user: context.request.actor
        )

        new(request: request, attack: attack)
      end

      # @return [Aikido::Zen::AttackWave::Request]
      attr_reader :request

      # @return [Aikido::Zen::AttackWave::Attack]
      attr_reader :attack

      # @param [Aikido::Zen::AttackWave::Request] the attack wave request
      # @param [Aikido::Zen::AttackWave::Attack] the attack wave attack
      # @param opts [Hash<Symbol, Object>] any other options to pass to
      #   the superclass initializer.
      # @return [Aikido::Zen::Events::AttackWave] an attack wave event
      def initialize(request:, attack:, **opts)
        super(type: "detected_attack_wave", **opts)
        @request = request
        @attack = attack
      end

      def as_json
        super.update(
          request: @attack.as_json,
          attack: @attack.as_json
        )
      end
    end
  end
end
