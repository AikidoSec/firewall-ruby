# frozen_string_literal: true

require_relative "auth_schemas"

module Aikido::Zen
  class Request::Schema
    class AuthDiscovery
      def initialize(context)
        @context = context
      end

      def schemas
        schemas = []
        schemas << extract_from_authorization_header if headers["Authorization"]
        schemas.concat(extract_from_headers)
        schemas.concat(extract_from_cookies)

        AuthSchemas.new(schemas)
      end

      private

      def extract_from_authorization_header
        type, _ = headers["Authorization"].to_s.split(/\s+/, 2)

        if AUTHORIZATION_SCHEMES.include?(type.to_s.downcase)
          AuthSchemas::Authorization.new(type)
        else
          AuthSchemas::ApiKey.new(:header, "Authorization")
        end
      end

      def extract_from_headers
        (headers.keys & COMMON_API_KEY_HEADERS)
          .map { |header| AuthSchemas::ApiKey.new(:header, header) }
      end

      def extract_from_cookies
        cookie_names = @context.payload_sources[:cookie].keys.map(&:downcase)

        (cookie_names & COMMON_COOKIE_NAMES)
          .map { |cookie| AuthSchemas::ApiKey.new(:cookie, cookie) }
      end

      def headers
        @context.request.normalized_headers
      end

      AUTHORIZATION_SCHEMES = %w[
        basic
        bearer
        digest
        dpop
        gnap
        hoba
        mutal
        negotiate
        privatetoken
        scram-sha-1
        scram-sha-256
        vapid
      ].freeze

      COMMON_API_KEY_HEADERS = %w[
        Apikey
        Api-Key
        Token
        X-Api-Key
        X-Token
      ]

      COMMON_COOKIE_NAMES = %w[
        user_id
        auth
        session
        jwt
        token
        sid
        connect.sid
        auth_token
        access_token
        refresh_token
      ]
    end
  end
end
