# frozen_string_literal: true

require_relative "request"

module Aikido::Agent
  # @return [Aikido::Agent::Request, nil] the ongoing HTTP request, or +nil+ if
  #   outside an HTTP request.
  def self.current_request
    Thread.current[:_aikido_current_request_]
  end

  def self.current_request=(request)
    Thread.current[:_aikido_current_request_] = request
  end

  # Rack middleware that keeps the current request in a Thread/Fiber-local
  # variable so that other parts of the agent/firewall can access it.
  class SetCurrentRequest
    def initialize(app)
      @app = app
    end

    def call(env)
      Aikido::Agent.current_request = Request.new(env)
      Aikido::Agent.track_request(Aikido::Agent.current_request)

      @app.call(env)
    ensure
      Aikido::Agent.current_request = nil
    end
  end
end
