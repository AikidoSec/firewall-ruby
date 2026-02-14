# frozen_string_literal: true

require "action_dispatch"

module Aikido::Zen
  class RailsEngine < ::Rails::Engine
    config.before_configuration do
      # Access library configuration at `Rails.application.config.zen`.
      config.zen = Aikido::Zen.config
    end

    initializer "aikido.add_middleware", after: :load_config_initializers do |app|
      # The Zen middleware is inserted in order as a block after the configured
      # middleware anchor point.

      middleware_block = [
        ::ActionDispatch::RemoteIp, # TODO: Avoid duplicate ActionDispatch::RemoteIp
        Aikido::Zen::Middleware::ForkDetector,
        Aikido::Zen::Middleware::ContextSetter,
        Aikido::Zen::Middleware::AllowedAddressChecker,
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
        # Due to how Rails sets up its middleware chain, the routing is evaluated
        # (and the Request object constructed) in the app that terminates the
        # chain, so no amount of middleware will be able to access it.
        #
        # This way, we overwrite the Request object as early as we can in the
        # request handling, so that by the time we start evaluating inputs, we
        # have assigned the request correctly.
        before_action { Aikido::Zen.current_context.update_request(request) }
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
