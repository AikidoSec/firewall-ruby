# frozen_string_literal: true

module Aikido::Agent
  class RailsEngine < ::Rails::Engine
    config.before_configuration do
      # Access library configuration at `Rails.application.config.aikido_agent`.
      config.aikido_agent = Aikido::Agent.config
    end

    initializer "aikido.add_middleware" do |app|
      app.middleware.use Aikido::Agent::SetCurrentRequest
    end

    initializer "aikido.configuration" do |app|
      app.config.aikido_agent.logger = Rails.logger.tagged("aikido")

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
