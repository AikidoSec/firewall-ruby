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
        if match
          index = match[1].to_i - 1
          return if index < 0

          params[index]
        end
      end

      def self.sqlite_placeholder_resolver(value, placeholder_number, params = [])
        return params[placeholder_number] unless placeholder_number.nil?

        case value
        when /^\?(\d+)$/
          match = Regexp.last_match

          index = match[1].to_i - 1
          return if index < 0

          params[index]
        when /^[:@$]([A-Za-z_][A-Za-z0-9_]*)$/
          match = Regexp.last_match

          key = match[1]

          params.flatten.each do |param|
            if Hash === param
              param.each do |param_key, param_value|
                return param_value if param_key.to_s == key
              end
            end
          end
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
          placeholder_resolver: method(:sqlite_placeholder_resolver)
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
