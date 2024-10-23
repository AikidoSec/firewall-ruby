# frozen_string_literal: true

require_relative "../request/schema/empty_schema"

class Aikido::Zen::Stats
  # @api private
  #
  # Keeps track of the visited routes.
  class Routes
    def initialize
      @routes = Hash.new do |h, k|
        h[k] = Record.new(0, Aikido::Zen::Request::Schema::EMPTY_SCHEMA)
      end
    end

    # @param route [Aikido::Zen::Route, nil] tracks the visit, if given.
    # @param schema [Aikido::Zen::Request::Schema, nil] the schema of the
    #   request, if the feature is enabled.
    # @return [void]
    def add(route, schema = nil)
      @routes[route].add(schema) if route
    end

    # @!visibility private
    def [](route)
      @routes[route]
    end

    # @!visibility private
    def empty?
      @routes.empty?
    end

    def as_json
      @routes.map do |route, record|
        {
          method: route.verb,
          path: route.path,
          hits: record.hits,
          apispec: record.schema&.as_json
        }.compact
      end
    end

    # @!visibility private
    Record = Struct.new(:hits, :schema) do
      def add(new_schema = nil)
        self.hits += 1
        self.schema |= new_schema
      end
    end
  end
end
