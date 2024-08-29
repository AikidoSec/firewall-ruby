# frozen_string_literal: true

require_relative "../request"
require_relative "../request/heuristic_router"

module Aikido::Agent
  # @!visibility private
  Context::RACK_REQUEST_BUILDER = ->(env) do
    delegate = Rack::Request.new(env)
    router = Aikido::Agent::Request::HeuristicRouter.new
    request = Aikido::Agent::Request.new(delegate, framework: "rails", router: router)

    Context.new(request) do |req|
      {
        query: req.GET,
        body: req.POST,
        route: {},
        header: req.normalized_headers,
        cookie: req.cookies,
        subdomain: []
      }
    end
  end
end
