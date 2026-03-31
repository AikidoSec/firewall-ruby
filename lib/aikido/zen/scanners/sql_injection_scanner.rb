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
        dialect = Aikido::Zen::SQL::Dialects.fetch(dialect)

        context.payloads.each do |payload|
          scanner = new(query, payload.value.to_s, dialect)
          next unless scanner.attack?

          return Attacks::SQLInjectionAttack.new(
            sink: sink,
            query: query,
            input: payload,
            dialect: dialect,
            context: context,
            operation: "#{sink.operation}.#{operation}",
            stack: Aikido::Zen.clean_stack_trace,
            failed_to_tokenize: scanner.failed_to_tokenize
          )
        rescue Aikido::Zen::InternalsError => error
          Aikido::Zen.config.logger.warn(error.message)
          scan.track_error(error, self)
        rescue => error
          scan.track_error(error, self)
        end

        nil
      end

      attr_reader :failed_to_tokenize

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
        return false if Aikido::Zen::Helpers.regexp_with_timeout(/\A[[:alnum:]_]+\z/i).match?(@input)

        # If the input is a comma-separated list of numbers, ignore it.
        return false if Aikido::Zen::Helpers.regexp_with_timeout(/\A[ ,]*\d[ ,\d]*\z/).match?(@input)

        result = Internals.detect_sql_injection(@query, @input, @dialect)

        case result
        when 0
          false
        when 1
          true
        when 3
          @failed_to_tokenize = true
          Aikido::Zen.config.block_invalid_sql?
        end
      rescue => err
        return true if defined?(Regexp::TimeoutError) && err.is_a?(Regexp::TimeoutError)

        raise err
      end
    end
  end
end
