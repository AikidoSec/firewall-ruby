# frozen_string_literal: true

require_relative "../context"

module Aikido::Zen
  # @!visibility private
  ENV_KEY = "aikido.context"

  module Middleware
    # Rack middleware that keeps the current context in a Thread/Fiber-local
    # variable so that other parts of the agent/firewall can access it.
    class ContextSetter
      def initialize(app)
        @app = app
      end

      def call(env)
        Aikido::Zen.current_context = env[ENV_KEY] = Context.from_rack_env(env)

        @app.call(env)
      ensure
        Aikido::Zen.current_context = nil
      end
    end
  end
end
