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
    # Duplicate the Rack environment to prevent unexpected modifications from
    # breaking Rails routing.
    duplicate_env = env.dup

    # Normalize PATH_INFO so routes are correctly recognized in middleware.
    duplicate_env["PATH_INFO"] = normalize_path(duplicate_env["PATH_INFO"]) if duplicate_env["PATH_INFO"]

    delegate = ActionDispatch::Request.new(duplicate_env)
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

  # @api private
  #
  # Normalizes a path by:
  #
  #   1. Collapsing consecutive forward slashes into a single forward slash.
  #   2. Removing forward trailing slash, unless the normalized path is "/".
  #
  # @param path [String] the path to normalize
  # @return [String] the normalized path
  def self.normalize_path(path)
    normalized_path = path.dup
    normalized_path.squeeze!("/")
    normalized_path.chomp!("/") unless normalized_path == "/"
    normalized_path
  end
end
