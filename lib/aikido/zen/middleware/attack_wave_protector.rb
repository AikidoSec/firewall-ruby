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

          context = @zen.current_context
          protect(context)

          response
        end

        # @api private
        # Visible for testing.
        def attack_wave?(context)
          @zen.attack_wave_detector.attack_wave?(context)
        end

        # @api private
        # Visible for testing.
        def protect(context)
          if attack_wave?(context)
            attack_wave = Aikido::Zen::Events::AttackWave.from_context(context)
            @zen.track_attack_wave(attack_wave)
            @zen.agent.report(attack_wave)
          end
        end
      end
    end
  end
end
