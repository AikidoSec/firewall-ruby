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

      # @param value [String]
      # @param placeholder_number [Integer, nil]
      # @param params [Array<Object>, nil]
      # @param sql [String, nil]
      # @return [Object]
      def self.common_placeholder_resolver(value, placeholder_number, params, sql: nil)
        return nil unless params

        params[placeholder_number] unless placeholder_number.nil?
      end

      # @param value [String]
      # @param placeholder_number [Integer, nil]
      # @param params [Array<Object>, nil]
      # @param sql [String, nil]
      # @return [Object]
      def self.postgresql_placeholder_resolver(value, placeholder_number, params, sql: nil)
        return nil unless params

        match = value.match(/^\$(\d+)$/)
        if match
          index = match[1].to_i - 1
          return if index < 0

          params[index]
        end
      end

      # @param value [String]
      # @param placeholder_number [Integer, nil]
      # @param params [Array<Object>, nil]
      # @param sql [String, nil]
      # @return [Object]
      def self.sqlite_placeholder_resolver(value, placeholder_number, params, sql: nil)
        return nil unless params

        # For bare `?` placeholders, the analyzer provides a placeholder_number
        # that represents the ordinal among bare `?` tokens only. However, SQLite's
        # parameter binding treats `?NNN` and `?` differently:
        # - `?NNN` binds to params[NNN - 1]
        # - Bare `?` binds sequentially starting after the highest `?NNN`
        #
        # The analyzer only tracks bare `?` and assigns ordinals (0, 1, 2...),
        # but it doesn't account for explicit `?NNN` placeholders. This creates
        # a mismatch when both forms are mixed in the same query.
        #
        # To prevent this bypass, we detect if the query contains any numbered
        # placeholders. If it does, we cannot trust the placeholder_number for
        # bare `?` placeholders and must fail safe by returning nil.
        if !placeholder_number.nil? && sql && sql.match?(/\?\d+/)
          # Mixed placeholders detected: the query contains both bare `?` and
          # numbered `?NNN` placeholders. We cannot reliably determine the correct
          # binding for bare `?` in this case, so we fail safe.
          return nil
        end

        # For queries with only bare `?` placeholders, the analyzer's ordinal
        # matches SQLite's sequential binding, so we can trust placeholder_number.
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
