# frozen_string_literal: true

module Aikido::Agent
  # @!visibility private
  Context::RAILS_REQUEST_BUILDER = ->(env) do
    request = ActionDispatch::Request.new(env)

    Context.new(request) do |request|
      {
        query: request.query_parameters,
        body: request.request_parameters,
        route: request.path_parameters
      }
    end
  end
end
