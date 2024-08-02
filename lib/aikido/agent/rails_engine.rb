# frozen_string_literal: true

module Aikido::Agent
  class RailsEngine < ::Rails::Engine
    initializer "aikido.add_middleware" do |app|
      app.middleware.use Aikido::Agent::SetCurrentRequest
    end

    config.after_initialize do
      # Make sure this is run at the end of the initialization process, so
      # that any gems required after aikido-firewall are detected and patched
      # accordingly.
      Aikido::Firewall.initialize!
    end
  end
end
