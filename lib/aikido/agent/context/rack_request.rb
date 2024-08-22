# frozen_string_literal: true

module Aikido::Agent
  # @!visibility private
  Context::RACK_REQUEST_BUILDER = ->(env) do
    Context.new(Rack::Request.new(env)) do |request|
      {
        query: request.GET,
        body: request.POST,
        route: {}
      }
    end
  end
end
