# frozen_string_literal: true

require_relative "definition"
require_relative "empty_schema"
require_relative "auth_discovery"

module Aikido::Zen
  class Request::Schema
    # @api private
    class Builder
      def initialize(context: Aikido::Zen.current_context, config: Aikido::Zen.config)
        @context = context
        @config = config
        @max_depth = @config.api_schema_collection_max_depth
        @max_props = @config.api_schema_collection_max_properties
      end

      def schema
        Request::Schema.new(
          content_type: body_data_type,
          body_schema: body_schema,
          query_schema: query_schema,
          auth_schema: AuthDiscovery.new(@context).schemas
        )
      end

      private

      def new(definition)
        Aikido::Zen::Request::Schema::Definition.new(definition)
      end

      def request
        @context.request
      end

      def body_data_type
        media_type = request.media_type.to_s

        # If the media type includes any tree other than the standard (vnd., prs.,
        # x., etc) and a suffix, then remove that bit and just keep the suffix,
        # which should tell us what the underlying data structure is.
        #
        # application/json               => application/json
        # application/vnd.github.v3+json => application/json
        media_type = media_type.sub(%r{/.*\+}, "/") if media_type.include?("+")

        DATA_TYPES.fetch(media_type, nil)
      end

      def query_schema
        return EMPTY_SCHEMA if request.query_string.to_s.empty?

        discover_schema(@context.payload_sources[:query])
      end

      def body_schema
        return EMPTY_SCHEMA if request.content_length.to_i.zero?

        discover_schema(sanitize_data(@context.payload_sources[:body]))
      end

      def discover_schema(object, depth: 0)
        case object
        when nil
          new(type: "null")
        when true, false
          new(type: "boolean")
        when String
          new(type: "string")
        when Integer
          new(type: "integer")
        when Numeric
          new(type: "number")
        when Array
          # If the array has at least one item, we assume it's homogeneous for
          # performance reasons, and so only inspect the type of the first one.
          sub_schema = {items: discover_schema(object.first, depth: depth + 1)} unless object.empty?
          new({type: "array"}.merge(sub_schema.to_h))
        when Hash
          object
            .take(@max_props)
            .each_with_object({type: "object", properties: {}}) { |(key, value), schema|
              break schema if depth >= @max_depth
              schema[:properties][key] = discover_schema(value, depth: depth + 1)
            }
            .then { |dfn| new(dfn) }
        end
      end

      # By default, Rails' automatic decoding wraps non Hash inputs in a Hash
      # with a _json key, so that the "params" object is always a Hash. So, for
      # example, the request body: '["this","is","json"]' is transformed to
      # '{"_json": ["this","is","json"]}' before being passed to the controller.
      #
      # We want to make sure to avoid this extra key when building the schema,
      # since we won't be able to play back requests with it.
      def sanitize_data(data)
        return data unless @context.request.framework == "rails"
        return data unless data.is_a?(Hash)

        if data.is_a?(Hash) && data.keys == ["_json"]
          data["_json"]
        else
          data
        end
      end

      DATA_TYPES = {
        "application/csp-report" => :json,
        "application/x-json" => :json,
        "application/json" => :json,

        "application/x-www-form-urlencoded" => :"form-urlencoded",

        "multipart/form-data" => :"form-data",

        "application/xml" => :xml,
        "text/xml" => :xml
      }
    end
  end
end
