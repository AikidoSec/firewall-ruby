# frozen_string_literal: true

require_relative "../request"
require_relative "../request/heuristic_router"

module Aikido::Zen
  # @!visibility private
  Context::RACK_REQUEST_BUILDER = ->(env) do
    # Normalize PATH_INFO so routes are correctly recognized in middleware.
    env["PATH_INFO"] = Helpers.normalize_path(env["PATH_INFO"])

    delegate = Rack::Request.new(env)
    router = Aikido::Zen::Request::HeuristicRouter.new
    request = Aikido::Zen::Request.new(delegate, framework: "rack", router: router)

    Context.new(request) do |req|
      query = begin
        req.GET
      rescue
        {}
      end

      # Parsing the request body reads rack.input and caches the result on env.
      # Ensure that rack.input can be rewound, create a copy of env and rewind
      # the rack.input stream so that the application can still read the full
      # request body and env does not cache the parsed result.
      body = begin
        env["rack.input"] = Helpers.rewindable(env["rack.input"])
        Rack::Request.new(env.dup).POST
      rescue
        {}
      ensure
        env["rack.input"]&.rewind
      end

      header = begin
        req.normalized_headers
      rescue
        {}
      end

      cookie = begin
        req.cookies
      rescue
        {}
      end

      {
        query: query,
        body: body,
        route: {},
        header: header,
        cookie: cookie,
        subdomain: []
      }
    end
  end
end
