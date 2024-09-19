# frozen_string_literal: true

require "delegate"

module Aikido::Zen
  module Scanners
    class SSRFScanner

      # @api private
      def initialize(request, input, redirects)
        @request = request
        @input = input
        @redirects = redirects
      end

      # @api private
      def attack?
        return false if @input.nil? || @input.to_s.empty?

        origins_for_request
          .product(uris_from_input)
          .any? { |(conn, uri)| match?(conn, uri) }
      end

      private

      def match?(conn_uri, input_uri)
        return false if conn_uri.hostname.nil? || conn_uri.hostname.empty?
        return false if input_uri.hostname.nil? || input_uri.hostname.empty?

        # The URI library will automatically set the port to the default port
        # for the current scheme if not provided, which means we can't just
        # check if the port is present, as it always will be.
        is_port_relevant = input_uri.port != input_uri.default_port
        return false if is_port_relevant && input_uri.port != conn_uri.port

        conn_uri.hostname == input_uri.hostname
      end

      def origins_for_request
        [@request.uri, @redirects.origin(@request.uri)].compact
      end

      # Maps the current user input into a Set of URIs we can check against:
      #
      # * The input itself, if it already looks like a URI.
      # * The input prefixed with http://
      # * The input prefixed with https://
      #
      # @return [Set<URI>]
      def uris_from_input
        input = @input.to_s

        # If you build a URI manually and set the hostname to an IPv6 string,
        # the URI library will be helpful to wrap it in brackets so it's a
        # valid hostname. We should do the same for the input.
        input = format("[%s]", input) if unescaped_ipv6?(input)

        [input, "http://#{input}", "https://#{input}"]
          .map { |candidate| as_uri(candidate) }
          .compact
          .uniq
      end

      def as_uri(string)
        URI(string)
      rescue URI::InvalidURIError
        nil
      end

      # Check if the input is an IPv6 that is not surrounded by square brackets.
      def unescaped_ipv6?(input)
        (
          IPAddr::RE_IPV6ADDRLIKE_FULL.match?(input) ||
          IPAddr::RE_IPV6ADDRLIKE_COMPRESSED.match?(input)
        ) && !(input.start_with?("[") && input.end_with?("]"))
      end

      # @api private
      class RedirectChains
        def initialize
          @redirects = {}
        end

        def add(source:, destination:)
          @redirects[destination] = source
          self
        end

        # Recursively looks for the original URI that triggered the current
        # chain. If given a URI that was not the result of a redirect chain, it
        # returns +nil+
        #
        # @param uri [URI]
        # @return [URI, nil]
        def origin(uri)
          source = @redirects[uri]

          if @redirects[source]
            origin(source)
          else
            source
          end
        end
      end
    end
  end
end
