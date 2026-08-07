# frozen_string_literal: true

require "action_dispatch"

module Aikido::Zen
  class RailsEngine < ::Rails::Engine
    # ActionController::Live runs the whole action in a new Thread so that
    # the original thread can be freed to handle the next request once the
    # response headers are committed.
    #
    # Zen stores the current context on the current Fiber, and propagates
    # this context to new Fibers created with Fiber.new. The root Fiber of
    # a new Thread is not created with Fiber.new so the current context is
    # not propagated automatically.
    #
    # Propagate the current context to the root Fiber of the new Thread
    # created by ActionController::Live to run the action.
    module LiveThreadContextSetter
      private

      def new_controller_thread(&blk)
        context = Aikido::Zen.current_context

        super do
          Fiber.current.aikido_current_context = context

          blk.call
        end
      end
    end

    config.before_configuration do
      # Access library configuration at `Rails.application.config.zen`.
      config.zen = Aikido::Zen.config
    end

    initializer "aikido.add_middleware", after: :load_config_initializers do |app|
      # The Zen middleware is inserted in order as a block after the configured
      # middleware anchor point.

      middleware_block = [
        Aikido::Zen::Middleware::ForkDetector,
        Aikido::Zen::Middleware::ContextSetter,
        Aikido::Zen::Middleware::AllowedAddressChecker,
        Aikido::Zen::Middleware::IPListChecker,
        Aikido::Zen::Middleware::UserAgentChecker,
        Aikido::Zen::Middleware::AttackProtector,
        Aikido::Zen::Middleware::AttackWaveProtector,
        # Request Tracker stats do not consider failed requests, so the middleware
        # must be the last one wrapping the request.
        Aikido::Zen::Middleware::RequestTracker
      ]

      middleware_anchor = Aikido::Zen.config.insert_middleware_after

      if middleware_anchor.nil?
        app.middleware.insert_before 0, middleware_block.first
      else
        app.middleware.insert_after middleware_anchor, middleware_block.first
      end

      middleware_block.each_cons(2) do |existing_middleware, middleware|
        app.middleware.insert_after(existing_middleware, middleware)
      end

      ActiveSupport.on_load(:action_controller) do
        ::ActionController::Live.prepend(Aikido::Zen::RailsEngine::LiveThreadContextSetter)

        before_action do
          Aikido::Zen.enable_idor_protection if Aikido::Zen.config.idor_protection_enabled?
        end

        # Due to how Rails sets up its middleware chain, the routing is evaluated
        # (and the Request object constructed) in the app that terminates the
        # chain, so no amount of middleware will be able to access it.
        #
        # This way, we overwrite the Request object as early as we can in the
        # request handling, so that by the time we start evaluating inputs, we
        # have assigned the request correctly.
        before_action { Aikido::Zen.current_context&.update_request(request) }
      end
    end

    initializer "aikido.configuration" do |app|
      app.config.zen.request_builder = Aikido::Zen::Context::RAILS_REQUEST_BUILDER

      # Plug Rails' JSON encoder/decoder, but only if the user hasn't changed
      # them for something else.
      if app.config.zen.json_encoder == Aikido::Zen::Config::DEFAULT_JSON_ENCODER
        app.config.zen.json_encoder = ActiveSupport::JSON.method(:encode)
      end

      if app.config.zen.json_decoder == Aikido::Zen::Config::DEFAULT_JSON_DECODER
        app.config.zen.json_decoder = ActiveSupport::JSON.method(:decode)
      end
    end

    config.after_initialize do
      # Start the Aikido Agent only once the application starts.
      Aikido::Zen.start!
    end
  end
end
