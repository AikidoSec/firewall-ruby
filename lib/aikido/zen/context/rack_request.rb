# frozen_string_literal: true

require_relative "../request"
require_relative "../request/heuristic_router"

module Aikido::Zen
  # @!visibility private
  Context::RACK_REQUEST_BUILDER = ->(env) do
    delegate = Rack::Request.new(env)
    router = Aikido::Zen::Request::HeuristicRouter.new
    request = Aikido::Zen::Request.new(delegate, framework: "rack", router: router)

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
