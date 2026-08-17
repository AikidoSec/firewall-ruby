# frozen_string_literal: true

module Aikido
  module Zen
    module Middleware
      class AttackWaveProtector
        def initialize(app, zen: Aikido::Zen)
          @app = app
          @zen = zen
        end

        def call(env)
          response = @app.call(env)
          status_code = response[0].to_i

          context = @zen.current_context
          protect(context, status_code)

          response
        end

        # @api private
        # @note Visible for testing.
        #
        # @param context [Aikido::Zen::Context]
        # @param status_code [Integer, nil]
        # @return [Array<Aikido::Zen::AttackWave::Sample>, nil]
        def detect_attack_wave(context, status_code = nil)
          request = context.request
          return nil if request.nil?

          return nil if @zen.request_bypassed?

          @zen.detect_attack_wave(context, status_code)
        end

        # @api private
        # @note Visible for testing.
        def protect(context, status_code = nil)
          samples = detect_attack_wave(context, status_code)
          return unless samples

          client_ip = context.request.client_ip

          request = Aikido::Zen::AttackWave::Request.new(
            ip_address: client_ip,
            user_agent: context.request.user_agent,
            source: context.request.framework
          )

          attack = Aikido::Zen::AttackWave::Attack.new(
            samples: samples,
            user: context.request.actor
          )

          attack_wave = Aikido::Zen::Events::AttackWave.new(
            request: request,
            attack: attack
          )

          @zen.track_attack_wave(attack_wave)
          @zen.agent.report(attack_wave)
        end
      end
    end
  end
end
