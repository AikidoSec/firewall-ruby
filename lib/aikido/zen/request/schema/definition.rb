# frozen_string_literal: true

require "forwardable"
require_relative "empty_schema"

module Aikido::Zen
  class Request::Schema
    # @api private
    #
    # The "JSON Schema"-like implementation that we extract from looking at the
    # request body and/or query string.
    class Definition
      extend Forwardable
      def_delegators :definition, :deconstruct_keys

      def initialize(definition)
        @definition = definition
      end

      # Recursively merges this schema definition with another one.
      #
      # * Properties missing in one or the other schemas are treated as optional.
      # * Merging any property with a null schema results in an optional schema.
      # * Number and Integer schemas are merged into Number schemas, since it's
      #   the more permissive of the types.
      #
      # Other than that, everything else just results in additive merging,
      # resulting in combining types together.
      #
      # @param other [Aikido::Zen::Request::Schema::Definition, nil]
      # @return [Aikido::Zen::Request::Schema::Definition]
      #
      # @see https://cswr.github.io/JsonSchema/spec/introduction/
      def merge(other)
        case [self, other]

        # Merging with itself or with nil results in just a copy
        in [obj, ^obj | nil | EMPTY_SCHEMA]
          dup

        # objects where at least one of them has properties
        in [{type: "object", properties: _}, {type: "object", properties: _}] |
           [{type: "object", properties: _}, {type: "object"}] |
           [{type: "object"}, {type: "object", properties: _}]
          left, right = definition[:properties], other.definition[:properties]
          merged_props = (left.keys.to_a | right.keys.to_a)
            .map { |key| [key, left.fetch(key, NULL).merge(right.fetch(key, NULL))] }
            .to_h
          new(definition.merge(other.definition).merge(properties: merged_props))

        # arrays where at least one of them has items
        in [{type: "array", items: _}, {type: "array", items: _}] |
           [{type: "array", items: _}, {type: "array"}] |
           [{type: "array"}, {type: "array", items: _}]
          items = [definition[:items], other.definition[:items]].compact.reduce(:merge)
          new(definition.merge(other.definition).merge({items: items}.compact))

        # x | x => x
        in {type: type}, {type: ^type}
          new(definition.merge(other.definition))

        # any | null => any?
        in {type: "null"}, {type: _}
          new(other.definition.merge(optional: true))
        in {type: _}, {type: "null"}
          new(definition.merge(optional: true))

        # number | integer => number
        in [{type: "integer"}, {type: "number"}] |
           [{type: "number"}, {type: "integer"}]
          new(definition.merge(other.definition).merge(type: "number"))

        # x | y => [x, y] if x != y
        else
          left_type, right_type = definition[:type], other.definition[:type]
          types = [left_type, right_type].flatten.uniq.sort
          new(definition.merge(other.definition).merge(type: types))

        end
      end
      alias_method :|, :merge

      def ==(other)
        as_json == other.as_json
      end

      def as_json
        definition
          .transform_keys(&:to_s)
          .transform_values do |val|
            val.respond_to?(:as_json) ? val.as_json : val
          end
      end

      def inspect
        format("#<%s %p>", self.class, definition)
      end

      protected

      attr_reader :definition

      private

      def new(definition)
        self.class.new(definition)
      end

      NULL = new(type: "null") # used as a stand-in to merge missing object props
    end
  end
end
