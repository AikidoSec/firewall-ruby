# frozen_string_literal: true

require_relative "../request"
require_relative "../request/rails_router"

module Aikido::Zen
  module Rails
    def self.router
      @router ||= Request::RailsRouter.new(::Rails.application.routes)
    end
  end

  # @!visibility private
  Context::RAILS_REQUEST_BUILDER = ->(env) do
    delegate = ActionDispatch::Request.new(env)
    request = Aikido::Zen::Request.new(
      delegate, framework: "rails", router: Rails.router
    )

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
