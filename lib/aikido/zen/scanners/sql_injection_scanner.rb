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
        dialect = Aikido::Zen::SQL::Dialects.fetch(dialect)

        context.payloads.each do |payload|
          next unless new(query, payload.value.to_s, dialect).attack?

          return Attacks::SQLInjectionAttack.new(
            sink: sink,
            query: query,
            input: payload,
            dialect: dialect,
            context: context,
            operation: "#{sink.operation}.#{operation}",
            stack: Aikido::Zen.clean_stack_trace
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
    end
  end
end
