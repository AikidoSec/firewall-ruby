# frozen_string_literal: true

require_relative "../request/schema/empty_schema"

module Aikido::Zen
  # @api private
  #
  # Keeps track of the visited routes.
  class Collector::Routes
    # @api private
    # Visible for testing.
    attr_reader :visits

    def initialize(config = Aikido::Zen.config)
      @config = config
      @visits = Hash.new { |h, k| h[k] = Record.new }
    end

    # @param route [Aikido::Zen::Route] the route of the request
    # @param schema [Aikido::Zen::Request::Schema] the schema for the request
    # @return [void]
    def add(route, schema)
      @visits[route].increment(schema) unless route.nil?
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
    # Visible for testing.
    def [](route)
      @visits[route]
    end

    # @api private
    def empty?
      @visits.empty?
    end

    # @api private
    Record = Struct.new(:hits, :schema, :samples) do
      def initialize(config = Aikido::Zen.config)
        super(0, Aikido::Zen::Request::Schema::EMPTY_SCHEMA, 0)
        @config = config
      end

      def increment(schema)
        self.hits += 1

        if sample_schema?
          self.samples += 1
          self.schema |= schema
        end
      end

      private

      def sample_schema?
        samples < @config.api_schema_max_samples
      end
    end
  end
end
