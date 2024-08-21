# frozen_string_literal: true

require_relative "../request"

module Aikido::Agent
  # @!visibility private
  Request::RAILS_REQUEST_BUILDER = ->(env) do
    delegate = ActionDispatch::Request.new(env)

    Request.new(delegate) do |request|
      {
        query: request.query_parameters,
        body: request.request_parameters,
        route: request.path_parameters
      }
    end
  end
end
