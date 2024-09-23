# frozen_string_literal: true

require "delegate"

module Aikido::Zen
  module Scanners
    class SSRFScanner
      # Checks if the connection being made is to a hostname supplied from user
      # input.
      #
      # @param request [Aikido::Zen::HTTP::OutboundRequest]
      # @param context [Aikido::Zen::Context]
      # @param sink [Aikido::Zen::Sink] the Sink that is running the scan.
      # @param operation [Symbol, String] name of the method being scanned.
      #   Expects +sink.operation+ being set to get the full module/name combo.
      #
      # @return [Aikido::Zen::Attacks::SSRFAttack, nil] an Attack if any user
      #   input is detected to be attempting SSRF, or +nil+ if not.
      def self.call(request:, sink:, context:, operation:, **)
        return if context.nil?

        context["ssrf.redirects"] ||= RedirectChains.new

        context.payloads.each do |payload|
          scanner = new(request, payload.value, context["ssrf.redirects"])
          next unless scanner.attack?

          attack = Attacks::SSRFAttack.new(
            sink: sink,
            request: request,
            input: payload,
            context: context,
            operation: "#{sink.operation}.#{operation}"
          )

          return attack
        end

        nil
      end

      # Track the origin of a redirection so we know if an attacker is using
      # redirect chains to mask their use of a (seemingly) safe domain.
      #
      # @param request [Aikido::Zen::HTTP::OutboundRequest]
      # @param response [Aikido::Zen::HTTP::OutboundResponse]
      # @param context [Aikido::Zen::Context]
      #
      # @return [void]
      def self.track_redirects(request:, response:, context: Aikido::Zen.current_context)
        return unless response.redirect?

        context["ssrf.redirects"] ||= RedirectChains.new
        context["ssrf.redirects"].add(
          source: request.uri,
          destination: response.redirect_to
        )
      end

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
