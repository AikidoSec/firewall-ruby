# frozen_string_literal: true

require_relative "context"

module Aikido::Agent
  # @return [Aikido::Agent::Context, nil]
  def self.current_context
    Thread.current[:_aikido_current_context_]
  end

  def self.current_context=(context)
    Thread.current[:_aikido_current_context_] = context
  end

  # Rack middleware that keeps the current context in a Thread/Fiber-local
  # variable so that other parts of the agent/firewall can access it.
  class SetContext
    def initialize(app)
      @app = app
    end

    def call(env)
      context = Context.from_rack_env(env)

      Aikido::Agent.current_context = context
      Aikido::Agent.track_request(context)

      @app.call(env)
    ensure
      Aikido::Agent.current_context = nil
    end
  end
end
