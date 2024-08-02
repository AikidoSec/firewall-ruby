# frozen_string_literal: true

module Aikido::Firewall
  module Vulnerabilities
    class SQLInjectionScanner
      # Checks if the given SQL query may have dangerous user input injected,
      # and raises an error if so, based on the current request.
      #
      # @param query [String]
      # @param request [Aikido::Agent::Request]
      #
      # @return [void]
      # @raise [Aikido::Firewall::SQLInjectionError] if an attack is detected.
      def self.scan(query, request: Aikido::Agent.current_request)
        # FIXME: This assumes queries executed outside of an HTTP request are
        # safe, but this is not the case. For example, if an HTTP request
        # enqueues a background job, passing user input verbatim, the job might
        # pass that input to a query without having a current request in scope.
        return if request.nil?

        request.each_user_input do |input|
          new(query, input).scan
        end
      end

      def initialize(query, input)
        @original_query, @original_input = query, input
        @query = query.downcase
        @input = input.downcase
      end

      def scan
        # If the input is longer than the query, then it is not part of it.
        return if @input.length > @query.length

        # If the input is not included in the query at all, then we are safe.
        return unless @query.include?(@input)

        # If the input is correctly escaped, we can ignore it.
        return if input_escaped_within_query?

        # TODO: Detect if the input has SQL or if it's e.g. an unescaped number.

        raise SQLInjectionError.new(@original_query, @original_input)
      end

      def input_escaped_within_query?
        segments_in_between = @query.split(@input)
        segments_in_between.each_cons(2) do |current_segment, next_segment|
          char_before_input = current_segment.last
          char_after_input = next_segment.first

          # FIXME: This is wrong but a simple enough first approximation to test
          # that this works for some simple cases.
          return false unless char_before_input == char_after_input &&
            QUOTE_CHARS.include?(char_before_input)
        end

        true
      end

      QUOTE_CHARS = %W[" ' `]
    end
  end
end
