# frozen_string_literal: true

module Aikido::Zen
  class Request::Schema
    # @!visibility private
    #
    # Singleton used as a placeholder until we get a schema for a request.
    # When "merged" it waits until a non-nil value is given and returns that.
    EMPTY_SCHEMA = Object.new

    class << EMPTY_SCHEMA
      # @!visibility private
      def merge(schema)
        schema || self
      end
      alias_method :|, :merge

      # @!visibility private
      def as_json
        nil
      end

      def inspect
        "#<Aikido::Zen::Schema EMPTY>"
      end
    end
  end
end
