# frozen_string_literal: true

require_relative "headers"

module Aikido::Zen
  module HTTP
    # This provides a uniform wrapper around outbound HTTP requests initiated
    # from the app, to provide a consistent API on top of all supported HTTP
    # libraries.
    class OutboundRequest
      prepend Headers

      attr_reader :verb
      attr_reader :uri

      def initialize(verb:, uri:)
        @verb = verb
        @uri = uri
      end
    end
  end
end
