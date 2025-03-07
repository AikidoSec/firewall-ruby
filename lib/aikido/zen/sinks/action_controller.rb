# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module ActionController
      # Implements the "middleware" for guard the gate (i.e.: rate-limiting or blocking)
      # in Rails apps, where we need to check at the end of the `before_action` chain,
      # rather than in an actual Rack middleware, to allow for calls to Zen.track_user being
      # made from before_actions in the host app, thus allowing guard the gate  by user ID
      # rather than solely by IP.
      class GateGuard
        def initialize(
          config: Aikido::Zen.config,
          settings: Aikido::Zen.runtime_settings,
          rate_limiter: Aikido::Zen::RateLimiter.new
        )
          @config = config
          @settings = settings
          @rate_limiter = rate_limiter
        end

        def block_pass?(controller)
          context = controller.request.env[Aikido::Zen::ENV_KEY]
          request = context.request

          if should_block_user?(request)
            status, headers, body = @config.blocked_responder.call(request, :user)
            controller.headers.update(headers)
            controller.render plain: Array(body).join, status: status

            return true
          end

          if should_throttle?(request)
            status, headers, body = @config.rate_limited_responder.call(request)
            controller.headers.update(headers)
            controller.render plain: Array(body).join, status: status

            return true
          end

          false
        end

        private

        def should_throttle?(request)
          return false if @settings.skip_protection_for_ips.include?(request.ip)

          @rate_limiter.throttle?(request)
        end

        # @param request [Aikido::Zen::Request]
        def should_block_user?(request)
          return false if request.actor.nil?

          @settings.blocked_user_ids&.include?(request.actor.id)
        end
      end

      def self.gate_guard
        @gate_guard ||= Aikido::Zen::Sinks::ActionController::GateGuard.new
      end

      module Extensions
        def run_callbacks(kind, *)
          return super unless kind == :process_action

          super do
            gate_guard = Aikido::Zen::Sinks::ActionController.gate_guard

            yield if block_given? && !gate_guard.block_pass?(self)
          end
        end
      end
    end
  end
end

::AbstractController::Callbacks.prepend(Aikido::Zen::Sinks::ActionController::Extensions)
