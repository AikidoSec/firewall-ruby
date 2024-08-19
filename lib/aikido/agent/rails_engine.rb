# frozen_string_literal: true

require "action_dispatch"
require_relative "request/rails_request"

module Aikido::Agent
  class RailsEngine < ::Rails::Engine
    config.before_configuration do
      # Access library configuration at `Rails.application.config.aikido_agent`.
      config.aikido_agent = Aikido::Agent.config
    end

    initializer "aikido.add_middleware" do |app|
      app.middleware.use Aikido::Agent::SetCurrentRequest

      # Due to how Rails sets up its middleware chain, the routing is evaluated
      # (and the Request object constructed) in the app that terminates the
      # chain, so no amount of middleware will be able to access it.
      #
      # This way, we overwrite the Request object as early as we can in the
      # request handling, so that by the time we start evaluating inputs, we
      # have assigned the request correctly.
      ActiveSupport.on_load(:action_controller) do
        before_action { Aikido::Agent.current_request.__setobj__(request) }
      end
    end

    initializer "aikido.configuration" do |app|
      app.config.aikido_agent.logger = Rails.logger.tagged("aikido")
      app.config.aikido_agent.request_builder = Aikido::Agent::Request::RAILS_REQUEST_BUILDER

      # Plug Rails' JSON encoder/decoder, but only if the user hasn't changed
      # them for something else.
      if app.config.aikido_agent.json_encoder == Aikido::Agent::Config::DEFAULT_JSON_ENCODER
        app.config.aikido_agent.json_encoder = ActiveSupport::JSON.method(:encode)
      end

      if app.config.aikido_agent.json_decoder == Aikido::Agent::Config::DEFAULT_JSON_DECODER
        app.config.aikido_agent.json_decoder = ActiveSupport::JSON.method(:decode)
      end
    end

    config.after_initialize do
      Aikido::Agent.initialize!

      # Make sure this is run at the end of the initialization process, so
      # that any gems required after aikido-firewall are detected and patched
      # accordingly.
      Aikido::Firewall.initialize!
    end
  end
end
