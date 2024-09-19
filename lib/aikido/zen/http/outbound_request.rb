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
      attr_reader :proxy

      def initialize(verb:, uri:, proxy: nil)
        @verb = verb
        @uri = uri
        @proxy = proxy
      end
    end
  end
end
