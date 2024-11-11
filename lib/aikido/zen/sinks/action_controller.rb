# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module ActionController
      # Implements the "middleware" for rate limiting in Rails apps, where we
      # need to check at the end of the `before_action` chain, rather than in
      # an actual Rack middleware, to allow for calls to Zen.track_user being
      # made from before_actions in the host app, thus allowing rate-limiting
      # by user ID rather than solely by IP.
      class Throttler
        def initialize(
          config: Aikido::Zen.config,
          settings: Aikido::Zen.runtime_settings,
          rate_limiter: Aikido::Zen::RateLimiter.new
        )
          @config = config
          @settings = settings
          @rate_limiter = rate_limiter
        end

        def throttle(controller)
          context = controller.request.env[Aikido::Zen::ENV_KEY]
          request = context.request

          if should_throttle?(request)
            status, headers, body = @config.rate_limited_responder.call(request)
            controller.headers.update(headers)
            controller.render plain: Array(body).join, status: status

            return true
          end

          false
        end

        private def should_throttle?(request)
          return false if @settings.skip_protection_for_ips.include?(request.ip)

          @rate_limiter.throttle?(request)
        end
      end

      def self.throttler
        @throttler ||= Aikido::Zen::Sinks::ActionController::Throttler.new
      end

      module Extensions
        def run_callbacks(kind, *)
          return super unless kind == :process_action

          super do
            rate_limiter = Aikido::Zen::Sinks::ActionController.throttler
            throttled = rate_limiter.throttle(self)

            yield if block_given? && !throttled
          end
        end
      end
    end
  end
end

::AbstractController::Callbacks.prepend(Aikido::Zen::Sinks::ActionController::Extensions)
