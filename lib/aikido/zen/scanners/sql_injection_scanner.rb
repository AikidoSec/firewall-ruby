# frozen_string_literal: true

require_relative "../attack"
require_relative "../internals"

module Aikido::Zen
  module Scanners
    class SQLInjectionScanner
      def self.skips_on_nil_context?
        true
      end

      # Checks if the given SQL query may have dangerous user input injected,
      # and returns an Attack if so, based on the current request.
      #
      # @param query [String]
      # @param dialect [Symbol] one of +:mysql+, +:postgesql+, or +:sqlite+.
      # @param scan [Aikido::Zen::Scan] the running scan.
      # @param sink [Aikido::Zen::Sink] the Sink that is running the scan.
      # @param context [Aikido::Zen::Context]
      # @param operation [Symbol, String] name of the method being scanned.
      #   Expects +sink.operation+ being set to get the full module/name combo.
      #
      # @return [Aikido::Zen::Attack, nil] an Attack if any user input is
      #   detected to be attempting a SQL injection, or nil if this is safe.
      def self.call(query:, dialect:, scan:, sink:, context:, operation:)
        dialect = DIALECTS.fetch(dialect) do
          Aikido::Zen.config.logger.warn "Unknown SQL dialect #{dialect.inspect}"
          DIALECTS[:common]
        end

        context.payloads.each do |payload|
          result = new(query, payload.value.to_s, dialect).detect

          next if result == 0
          next if result == 3 && !Aikido::Zen.config.block_invalid_sql?

          return Attacks::SQLInjectionAttack.new(
            sink: sink,
            query: query,
            input: payload,
            dialect: dialect,
            context: context,
            operation: "#{sink.operation}.#{operation}",
            stack: Aikido::Zen.clean_stack_trace,
            failed_to_tokenize: result == 3
          )
        rescue Aikido::Zen::InternalsError => error
          Aikido::Zen.config.logger.warn(error.message)
          scan.track_error(error, self)
        rescue => error
          scan.track_error(error, self)
        end

        nil
      end

      def initialize(query, input, dialect)
        @query = query.downcase
        @input = input.downcase
        @dialect = dialect
      end

      def should_return_early?
        # Ignore single char inputs since they shouldn't be able to do much harm
        return true if @input.length <= 1

        # If the input is longer than the query, then it is not part of it
        return true if @input.length > @query.length

        # If the input is not included in the query at all, then we are safe
        return true unless @query.include?(@input)

        # If the input is solely alphanumeric, we can ignore it
        return true if Aikido::Zen::Helpers.regexp_with_timeout(/\A[[:alnum:]_]+\z/i).match?(@input)

        # If the input is a comma-separated list of numbers, ignore it.
        return true if Aikido::Zen::Helpers.regexp_with_timeout(/\A[ ,]*\d[ ,\d]*\z/).match?(@input)

        false
      rescue => err
        return false if defined?(Regexp::TimeoutError) && err.is_a?(Regexp::TimeoutError)

        raise err
      end

      def detect
        return 0 if should_return_early?
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
