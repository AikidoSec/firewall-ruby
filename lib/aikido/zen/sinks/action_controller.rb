# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module ActionController
      # Implements the "middleware" for blocking requests (i.e.: rate-limiting or blocking
      # user/bots) in Rails apps, where we need to check at the end of the `before_action`
      # chain, rather than in an actual Rack middleware, to allow for calls to
      # `Zen.track_user` being made from before_actions in the host app, thus allowing
      # block/rate-limit by user ID rather than solely by IP.
      class BlockRequestChecker
        def initialize(
          config: Aikido::Zen.config,
          settings: Aikido::Zen.runtime_settings,
          detached_agent: Aikido::Zen.detached_agent
        )
          @config = config
          @settings = settings
          @detached_agent = detached_agent
        end

        def block?(controller)
          return false unless controller.respond_to?(:request)

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

        private def should_throttle?(request)
          # Bypass rate limiting for allowed IPs
          return false if @settings.allowed_ips.include?(request.ip)

          return false unless @settings.endpoints[request.route].rate_limiting.enabled?

          result = @detached_agent.calculate_rate_limits(request)
          return false unless result

          request.env["aikido.rate_limiting"] = result
          request.env["aikido.rate_limiting"].throttled?
        end

        # @param request [Aikido::Zen::Request]
        private def should_block_user?(request)
          return false if request.actor.nil?

          Aikido::Zen.runtime_settings.blocked_user_ids&.include?(request.actor.id)
        end
      end

      def self.block_request_checker
        @block_request_checker ||= Aikido::Zen::Sinks::ActionController::BlockRequestChecker.new
      end

      module Extensions
        def run_callbacks(kind, *)
          return super unless kind == :process_action

          super do
            checker = Aikido::Zen::Sinks::ActionController.block_request_checker

            yield if block_given? && !checker.block?(self)
          end
        end
      end
    end
  end
end

::AbstractController::Callbacks.prepend(Aikido::Zen::Sinks::ActionController::Extensions)
