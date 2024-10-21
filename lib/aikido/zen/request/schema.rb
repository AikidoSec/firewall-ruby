# frozen_string_literal: true

require "forwardable"

module Aikido::Zen
  # Defines the shape of a request received by your application as seen by Zen.
  # This is used to understand how requests are made against your app, so
  # dynamic security testing on your API endpoints can take place.
  #
  # @see Aikido::Zen::Config#api_schema_collection_enabled?
  class Request::Schema
    # @return [Symbol, nil] an identifier for the Content-Type header of the
    #   request, if sent.
    attr_reader :content_type

    # @return [Aikido::Zen::Request::Schema::Definition]
    attr_reader :body_schema

    # @return [Aikido::Zen::Request::Schema::Definition]
    attr_reader :query_schema

    # @return [Aikido::Zen::Request::Schema::AuthSchemas]
    attr_reader :auth_schema

    # Extracts the request information from the current Context (if configured)
    # and builds a Schema out of it.
    #
    # @param context [Aikido::Zen::Context, nil]
    # @return [Aikido::Zen::Request::Schema, nil]
    def self.build(context = Aikido::Zen.current_context)
      return if context.nil?

      Request::Schema::Builder.new(context: context).schema
    end

    def initialize(content_type:, body_schema:, query_schema:, auth_schema:)
      @content_type = content_type
      @query_schema = query_schema
      @body_schema = body_schema
      @auth_schema = auth_schema
    end

    # @return [Hash]
    def as_json
      body = {type: content_type, schema: body_schema.as_json}.compact
      body = nil if body.empty?

      {body: body, query: query_schema.as_json, auth: auth_schema.as_json}.compact
    end

    # Merges the request specification with another request's specification.
    #
    # @param other [Aikido::Zen::Request::Schema, nil]
    # @return [Aikido::Zen::Request::Schema]
    def merge(other)
      return self if other.nil?

      self.class.new(
        # TODO: this is currently overriding the content type with the new
        # value, but we should support APIs that accept input in many types
        # (e.g. JSON and XML)
        content_type: other.content_type,
        body_schema: body_schema.merge(other.body_schema),
        query_schema: query_schema.merge(other.query_schema),
        auth_schema: auth_schema.merge(other.auth_schema)
      )
    end
    alias_method :|, :merge
  end
end

require_relative "schema/builder"
