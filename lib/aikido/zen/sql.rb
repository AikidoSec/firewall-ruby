# frozen_string_literal: true

module Aikido::Zen
  module SQL
    module Dialects
      # @api private
      Dialect = Struct.new(:name, :internals_key, :placeholder_resolver, keyword_init: true) do
        alias_method :to_s, :name
        alias_method :to_int, :internals_key

        def resolve_placeholder(*args, **kwargs)
          placeholder_resolver.call(*args, **kwargs)
        end
      end

      def self.common_placeholder_resolver(value, placeholder_number, params = [])
        params[placeholder_number] unless placeholder_number.nil?
      end

      def self.postgresql_placeholder_resolver(value, placeholder_number, params = [])
        match = value.match(/^\$(\d+)$/)
        if match && params
          index = match[1].to_i - 1
          params[index]
        end
      end

      # Maps easy-to-use Symbols to a struct that keeps both the name and the
      # internal identifier used by libzen.
      #
      # @see https://github.com/AikidoSec/zen-internals/blob/main/src/sql_injection/helpers/select_dialect_based_on_enum.rs
      DIALECTS = {
        common: Dialect.new(
          name: "SQL",
          internals_key: 0,
          placeholder_resolver: method(:common_placeholder_resolver)
        ),
        mysql: Dialect.new(
          name: "MySQL",
          internals_key: 8,
          placeholder_resolver: method(:common_placeholder_resolver)
        ),
        postgresql: Dialect.new(
          name: "PostgreSQL",
          internals_key: 9,
          placeholder_resolver: method(:postgresql_placeholder_resolver)
        ),
        sqlite: Dialect.new(
          name: "SQLite",
          internals_key: 12,
          placeholder_resolver: method(:common_placeholder_resolver)
        )
      }.freeze

      # @param dialect [Symbol]
      # @return [Aikido::Zen::SQL::Dialects::Dialect]
      def self.fetch(dialect)
        DIALECTS.fetch(dialect, DIALECTS[:common])
      end
    end
  end
end
