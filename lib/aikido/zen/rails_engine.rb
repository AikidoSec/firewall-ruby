# frozen_string_literal: true

require "action_dispatch"

module Aikido::Zen
  class RailsEngine < ::Rails::Engine
    config.before_configuration do
      # Access library configuration at `Rails.application.config.zen`.
      config.zen = Aikido::Zen.config
    end

    initializer "aikido.add_middleware" do |app|
      next if config.zen.disabled?

      app.middleware.use Aikido::Zen::Middleware::SetContext
      app.middleware.use Aikido::Zen::Middleware::CheckAllowedAddresses

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
      # Allow the logger to be configured before checking if disabled? so we can
      # let the user know that the agent is disabled.
      app.config.zen.logger = ::Rails.logger.tagged("aikido")

      next if config.zen.disabled?

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
      if config.zen.disabled?
        config.zen.logger.warn("Zen has been disabled and will not run.")
        next
      end

      # Make sure this is run at the end of the initialization process, so
      # that any gems required after aikido-zen are detected and patched
      # accordingly.
      Aikido::Zen.load_sinks!
    end
  end
end
