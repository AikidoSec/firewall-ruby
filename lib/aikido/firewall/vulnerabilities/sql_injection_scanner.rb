# frozen_string_literal: true

require_relative "sql_injection/sql_dialect"
require_relative "../attack"

module Aikido::Firewall
  module Vulnerabilities
    class SQLInjectionScanner
      # Checks if the given SQL query may have dangerous user input injected,
      # and returns an Attack if so, based on the current request.
      #
      # @param query [String]
      # @param context [Aikido::Agent::Context]
      # @param sink [Aikido::Firewall::Sink] the Sink that is running the scan.
      # @param dialect [Symbol] one of +:mysql+, +:postgesql+, or +:sqlite+.
      # @param operation [Symbol, String] name of the method being scanned.
      #   Expects +sink.operation+ being set to get the full module/name combo.
      #
      # @return [Aikido::Firewall::Attack, nil] an Attack if any user input is
      #   detected to be attempting a SQL injection, or nil if this is safe.
      def self.call(query:, dialect:, sink:, context:, operation:)
        # FIXME: This assumes queries executed outside of an HTTP request are
        # safe, but this is not the case. For example, if an HTTP request
        # enqueues a background job, passing user input verbatim, the job might
        # pass that input to a query without having a current request in scope.
        return if context.nil?

        context.payloads.each do |payload|
          scanner = new(query, payload.value, dialect)
          next unless scanner.attack?

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

      # @api private
      def initialize(query, input, dialect)
        @query = query.downcase
        @input = input.downcase
        @dialect = SQLInjection[dialect]
      end

      # @api private
      def attack?
        # Ignore single char inputs since they shouldn't be able to do much harm
        return false if @input.length <= 1

        # If the input is longer than the query, then it is not part of it
        return false if @input.length > @query.length

        # If the input is not included in the query at all, then we are safe
        return false unless @query.include?(@input)

        # If the input is correctly quoted/escaped, we can ignore it
        return false if input_quoted_or_escaped_within_query?

        # If the input is solely alphanumeric, we can ignore it
        return false if /\A[[:alnum:]]+\z/i.match?(@input)

        # The last thing to check is whether the input contains SQL syntax.
        @dialect.match?(@input)
      end

      # @api private
      def input_quoted_or_escaped_within_query?
        segments_in_between = @query.split(@input)

        # Special case to make sure each_cons does the right thing when the
        # query starts/ends in the user input.
        segments_in_between.unshift "" if @query.start_with?(@input)
        segments_in_between.push "" if @query.end_with?(@input)

        segments_in_between.each_cons(2) do |current_segment, next_segment|
          input = @input

          char_before_input = current_segment[-1]
          char_after_input = next_segment[0]

          QUOTE_CHARS.each do |quote|
            # Special case when the input starts with a single quote but it is
            # correctly escaped, such as:
            #
            #   input: 'hello
            #   query: ...WHERE id = '\\'hello'
            #
            # In this case, we remove the `\\'`, leaving the char_before_input
            # and char_after_input to both be `'`, which results in the check
            # being successful.
            if input.start_with?(quote) && char_before_input == "\\" &&
                current_segment[-2] == quote && char_after_input == quote
              char_before_input = quote
              input = input[1..] # remove the quote from the start
              break
            end
          end

          return false if char_before_input != char_after_input

          return false unless QUOTE_CHARS.include?(char_before_input)

          return false if input.include?(char_before_input)

          return false if input.gsub(ALLOWED_ESCAPE_SEQUENCES, "").include?("\\")
        end

        true
      end

      QUOTE_CHARS = %w[" ' `]

      ALLOWED_ESCAPE_SEQUENCES = /\\n|\\r|\\t/
    end
  end
end
