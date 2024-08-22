# frozen_string_literal: true

require_relative "../request"

module Aikido::Agent
  # @!visibility private
  Context::RACK_REQUEST_BUILDER = ->(env) do
    delegate = Rack::Request.new(env)
    request = Aikido::Agent::Request.new(delegate)

    Context.new(request) do |req|
      {
        query: req.GET,
        body: req.POST,
        route: {}
      }
    end
  end
end
