# frozen_string_literal: true

require_relative "headers"

module Aikido::Zen
  module HTTP
    # Provides a uniform wrapper around responses from outbound HTTP requests
    # initiated by the app, to provide a consistent API on top of all supported
    # HTTP libraries.
    class OutboundResponse
      prepend Headers

      def initialize(status:)
        @status = status
      end

      def redirect?
        @status.to_s.start_with?("3") && headers["location"]
      end

      def redirect_to
        headers["location"] if redirect?
      end
    end
  end
end
