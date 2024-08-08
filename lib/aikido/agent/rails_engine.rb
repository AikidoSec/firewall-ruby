# frozen_string_literal: true

module Aikido::Agent
  class RailsEngine < ::Rails::Engine
    initializer "aikido.add_middleware" do |app|
      app.middleware.use Aikido::Agent::SetCurrentRequest
    end

    initializer "aikido.configuration" do |app|
      # Access library configuration at `Rails.application.config.aikido_agent`.
      app.config.aikido_agent = lib_config = Aikido::Agent.config

      # Plug Rails' JSON encoder/decoder, but only if the user hasn't changed
      # them for something else.
      if lib_config.json_encoder == Aikido::Agent::Config::DEFAULT_JSON_ENCODER
        lib_config.json_encoder = ActiveSupport::JSON.method(:encode)
      end

      if lib_config.json_decoder == Aikido::Agent::Config::DEFAULT_JSON_DECODER
        lib_config.json_decoder = ActiveSupport::JSON.method(:decode)
      end
    end

    config.after_initialize do
      # Make sure this is run at the end of the initialization process, so
      # that any gems required after aikido-firewall are detected and patched
      # accordingly.
      Aikido::Firewall.initialize!
    end
  end
end
