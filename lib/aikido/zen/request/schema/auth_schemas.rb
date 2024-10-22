# frozen_string_literal: true

module Aikido::Zen
  class Request::Schema
    class AuthSchemas
      attr_reader :schemas

      def initialize(schemas)
        @schemas = schemas
      end

      def merge(other)
        self.class.new((schemas + other.schemas).uniq)
      end
      alias_method :|, :merge

      def as_json
        @schemas.map(&:as_json) unless @schemas.empty?
      end

      def ==(other)
        other.is_a?(self.class) && schemas == other.schemas
      end

      NONE = new([])

      Authorization = Struct.new(:scheme) do
        def as_json
          {type: "http", scheme: scheme.downcase}
        end
      end

      ApiKey = Struct.new(:location, :name) do
        def as_json
          {type: "apiKey", in: location, name: name}.compact
        end
      end
    end
  end
end
