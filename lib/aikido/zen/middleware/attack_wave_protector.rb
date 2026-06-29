# frozen_string_literal: true

module Aikido
  module Zen
    module Middleware
      class AttackWaveProtector
        def initialize(app, zen: Aikido::Zen, settings: Aikido::Zen.runtime_settings)
          @app = app
          @zen = zen
          @settings = settings
        end

        def call(env)
          response = @app.call(env)
          status_code = response[0].to_i

          context = @zen.current_context
          protect(context, status_code)

          response
        end

        # @api private
        # Visible for testing.
        def attack_wave?(context, status_code = nil)
          request = context.request
          return false if request.nil?

          return false if @settings.bypassed_ips.include?(request.client_ip)

          @zen.attack_wave_detector.attack_wave?(context, status_code)
        end

        # @api private
        # Visible for testing.
        def protect(context, status_code = nil)
          if attack_wave?(context, status_code)
            client_ip = context.request.client_ip

            request = Aikido::Zen::AttackWave::Request.new(
              ip_address: client_ip,
              user_agent: context.request.user_agent,
              source: context.request.framework
            )

            samples = @zen.attack_wave_detector.samples[client_ip].to_a

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
end
