# frozen_string_literal: true

require_relative "../request"

module Aikido::Agent
  # @!visibility private
  Context::RAILS_REQUEST_BUILDER = ->(env) do
    delegate = ActionDispatch::Request.new(env)
    request = Aikido::Agent::Request.new(delegate, framework: "rails")

    decrypt_cookies = ->(req) do
      return req.cookies unless req.respond_to?(:cookie_jar)

      req.cookie_jar.map { |key, value|
        plain_text = req.cookie_jar.encrypted[key].presence ||
          req.cookie_jar.signed[key].presence ||
          value
        [key, plain_text]
      }.to_h
    end

    Context.new(request) do |req|
      {
        query: req.query_parameters,
        body: req.request_parameters,
        route: req.path_parameters,
        header: req.normalized_headers,
        cookie: decrypt_cookies.call(req),
        subdomain: req.subdomains
      }
    end
  end
end
