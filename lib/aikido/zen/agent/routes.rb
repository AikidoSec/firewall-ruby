# frozen_string_literal: true

require_relative "../request/schema/empty_schema"

module Aikido::Zen
  # @api private
  #
  # Keeps track of the visited routes.
  class Agent::Routes
    def initialize
      @visits = Hash.new { |h, k| h[k] = Record.new }
    end

    # @param route [Aikido::Zen::Route, nil] tracks the visit, if given.
    # @param schema [Aikido::Zen::Request::Schema, nil] the schema of the
    #   request, if the feature is enabled.
    # @return [self]
    def add(route, schema = nil)
      @visits[route].increment(schema) unless route.nil?
      self
    end

    def as_json
      @visits.map do |route, record|
        {
          method: route.verb,
          path: route.path,
          hits: record.hits,
          apispec: record.schema.as_json
        }.compact
      end
    end

    # @api private
    def [](route)
      @visits[route]
    end

    # @api private
    def empty?
      @visits.empty?
    end

    # @api private
    Record = Struct.new(:hits, :schema) do
      def initialize
        super(0, Aikido::Zen::Request::Schema::EMPTY_SCHEMA)
      end

      def increment(schema)
        self.hits += 1
        self.schema |= schema if schema
      end
    end
  end
end
