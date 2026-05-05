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
    # Normalize PATH_INFO so routes are correctly recognized in middleware.
    env["PATH_INFO"] = Helpers.normalize_path(env["PATH_INFO"])

    # Duplicate the Rack environment to prevent unexpected modifications from
    # breaking Rails routing.
    delegate = ActionDispatch::Request.new(env.dup)
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
      query = req.query_parameters rescue {}
      body = req.request_parameters rescue {}
      route = req.path_parameters rescue {}
      header = req.normalized_headers rescue {}
      cookie = decrypt_cookies.call(req) rescue {}
      subdomain = req.subdomains rescue []

      {
        query: query,
        body: body,
        route: route,
        header: header,
        cookie: cookie,
        subdomain: subdomain
      }
    end
  end
end
