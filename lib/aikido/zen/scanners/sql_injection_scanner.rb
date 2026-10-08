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
        @original_query = query
        @original_input = input
        @query = Aikido::Zen::Helpers.encode_safely(query).downcase
        @input = Aikido::Zen::Helpers.encode_safely(input).downcase.strip
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

        # Check if the query or input contains invalid UTF-8 or binary data that could
        # be interpreted differently by the database under a multibyte encoding (e.g., GBK).
        # If lossy encoding occurred, block the query to prevent encoding-based SQL injection bypasses.
        if encoding_mismatch_detected?
          @failed_to_tokenize = true
          return Aikido::Zen.config.block_invalid_sql?
        end

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

      private

      # Detects if the query or input underwent lossy encoding transformation that could
      # lead to a parser differential between the scanner and the database.
      #
      # This prevents attacks where multibyte database encodings (e.g., GBK) interpret
      # byte sequences differently than UTF-8, allowing SQL injection to bypass detection.
      # For example, the byte sequence BF 5C 27 under GBK has BF 5C as one multibyte
      # character followed by 27 (quote), but after UTF-8 scrubbing, BF becomes U+FFFD
      # and 5C appears as a backslash that seems to escape the quote.
      #
      # @return [Boolean] true if encoding mismatch is detected
      def encoding_mismatch_detected?
        # Check if the input had invalid UTF-8 or was binary
        # We focus on input because that's what contains user-controlled data
        input_is_binary = @original_input.encoding == Encoding::BINARY
        input_has_invalid_utf8 = !@original_input.valid_encoding?

        # If the input is binary or has invalid UTF-8, check if transformation was lossy
        if input_is_binary || input_has_invalid_utf8
          # Encode the input to see what the scanner will analyze
          encoded_input = Aikido::Zen::Helpers.encode_safely(@original_input)
          
          # Compare the binary representations to detect lossy transformation
          # If bytes changed, the scanner sees different data than what the database executes
          input_bytes_changed = @original_input.b != encoded_input.b
          
          # Flag as suspicious if the transformation was lossy
          # This indicates a potential parser differential between scanner and database
          return true if input_bytes_changed
        end

        false
      end
    end
  end
end
