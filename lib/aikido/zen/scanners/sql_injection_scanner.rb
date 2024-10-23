# frozen_string_literal: true

require_relative "../attack"
require_relative "../internals"

module Aikido::Zen
  module Scanners
    class SQLInjectionScanner
      # Checks if the given SQL query may have dangerous user input injected,
      # and returns an Attack if so, based on the current request.
      #
      # @param query [String]
      # @param context [Aikido::Zen::Context]
      # @param sink [Aikido::Zen::Sink] the Sink that is running the scan.
      # @param dialect [Symbol] one of +:mysql+, +:postgesql+, or +:sqlite+.
      # @param operation [Symbol, String] name of the method being scanned.
      #   Expects +sink.operation+ being set to get the full module/name combo.
      #
      # @return [Aikido::Zen::Attack, nil] an Attack if any user input is
      #   detected to be attempting a SQL injection, or nil if this is safe.
      #
      # @raise [Aikido::Zen::InternalsError] if an error occurs when loading or
      #   calling zenlib. See Sink#scan.
      def self.call(query:, dialect:, sink:, context:, operation:)
        # FIXME: This assumes queries executed outside of an HTTP request are
        # safe, but this is not the case. For example, if an HTTP request
        # enqueues a background job, passing user input verbatim, the job might
        # pass that input to a query without having a current request in scope.
        return if context.nil?

        dialect = DIALECTS.fetch(dialect) do
          Aikido::Zen.config.logger.warn "Unknown SQL dialect #{dialect.inspect}"
          DIALECTS[:common]
        end

        context.payloads.each do |payload|
          next unless new(query, payload.value, dialect).attack?

          return Attacks::SQLInjectionAttack.new(
            sink: sink,
            query: query,
            input: payload,
            dialect: dialect,
            context: context,
            operation: "#{sink.operation}.#{operation}"
          )
        end

        nil
      end

      def initialize(query, input, dialect)
        @query = query.downcase
        @input = input.downcase
        @dialect = dialect
      end

      def attack?
        # Ignore single char inputs since they shouldn't be able to do much harm
        return false if @input.length <= 1

        # If the input is longer than the query, then it is not part of it
        return false if @input.length > @query.length

        # If the input is not included in the query at all, then we are safe
        return false unless @query.include?(@input)

        # If the input is solely alphanumeric, we can ignore it
        return false if /\A[[:alnum:]_]+\z/i.match?(@input)

        # If the input is a comma-separated list of numbers, ignore it.
        return false if /\A(?:\d+(?:,\s*)?)+\z/i.match?(@input)

        Internals.detect_sql_injection(@query, @input, @dialect)
      end

      # @api private
      Dialect = Struct.new(:name, :internals_key, keyword_init: true) do
        alias_method :to_s, :name
        alias_method :to_int, :internals_key
      end

      # Maps easy-to-use Symbols to a struct that keeps both the name and the
      # internal identifier used by libzen.
      #
      # @see https://github.com/AikidoSec/zen-internals/blob/main/src/sql_injection/helpers/select_dialect_based_on_enum.rs
      DIALECTS = {
        common: Dialect.new(name: "SQL", internals_key: 0),
        mysql: Dialect.new(name: "MySQL", internals_key: 8),
        postgresql: Dialect.new(name: "PostgreSQL", internals_key: 9),
        sqlite: Dialect.new(name: "SQLite", internals_key: 12)
      }
    end
  end
end
