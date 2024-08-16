# frozen_string_literal: true

require "action_dispatch"

module Aikido::Agent
  # @return [ActionDispatch::Request, nil] the ongoing HTTP request, or +nil+ if
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
      @app.call(env)
    ensure
      Aikido::Agent.current_request = nil
    end
  end

  class Request < ActionDispatch::Request
    # Yields every non-empty input in the request (whether a query param, path
    # param, or request body param).
    #
    # @return [void]
    def each_user_input
      # FIXME: This does not yet consider nested hashes
      params.each_value { |v| yield v if v.present? }
    end

    # TODO: Implement me
    def as_json
      {method: method}
    end
  end
end
