# frozen_string_literal: true

module Aikido::Zen
  module HTTP
    # @api private
    #
    # Provides a way to access request/response headers consistently. All keys
    # are downcased, and each sink can provide a lambda to normalize the values
    # (since some HTTP libraries return the header values as arrays, and some as
    # strings).
    module Headers
      # @param headers [Hash<String, Object>]
      # @param header_normalizer [Proc{Object => String}]
      def initialize(headers:, header_normalizer: :to_s.to_proc, **opts)
        super(**opts)

        @headers = headers
        @header_normalizer = header_normalizer
        @normalized_headers = false
      end

      # @return [Hash<String, String>]
      def headers
        return @headers if @normalized_headers

        @headers
          .transform_keys!(&:downcase)
          .transform_values!(&@header_normalizer)
          .tap { @normalized_headers = true }
      end
    end
  end
end
