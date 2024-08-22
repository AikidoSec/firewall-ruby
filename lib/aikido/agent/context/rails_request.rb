# frozen_string_literal: true

require_relative "../request"

module Aikido::Agent
  # @!visibility private
  Context::RAILS_REQUEST_BUILDER = ->(env) do
    delegate = ActionDispatch::Request.new(env)
    request = Aikido::Agent::Request.new(delegate, framework: "rails")

    Context.new(request) do |req|
      {
        query: req.query_parameters,
        body: req.request_parameters,
        route: req.path_parameters,
        header: req.normalized_headers
      }
    end
  end
end
