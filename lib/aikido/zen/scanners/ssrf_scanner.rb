# frozen_string_literal: true

require_relative "ssrf/private_ip_checker"

module Aikido::Zen
  module Scanners
    class SSRFScanner
      # Checks if the connection being made is to a hostname supplied from user
      # input.
      #
      # @param request [Aikido::Zen::Scanners::SSRFScanner::Request]
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
          scanner = new(request.uri, payload.value, context["ssrf.redirects"])
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
      # @param request [Aikido::Zen::Scanners::SSRFScanner::Request]
      # @param response [Aikido::Zen::Scanners::SSRFScanner::Response]
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
      def initialize(request_uri, input, redirects)
        @request_uri = request_uri
        @input = input
        @redirects = redirects
      end

      # @api private
      def attack?
        return false if @input.nil? || @input.to_s.empty?

        # If the request is not aimed at an internal IP, we can ignore it. (It
        # might still be an SSRF if defined strictly, but it's unlikely to be
        # exfiltrating data from the app's servers, and the risk for false
        # positives is too high.)
        return false unless private_ip?(@request_uri.hostname)

        origins_for_request
          .product(uris_from_input)
          .any? { |(conn_uri, candidate)| match?(conn_uri, candidate) }
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

      def private_ip?(hostname)
        @private_ip_checker ||= SSRF::PrivateIPChecker.new
        @private_ip_checker.private?(hostname)
      end

      def origins_for_request
        [@request_uri, @redirects.origin(@request_uri)].compact
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
      module Headers
        # @param headers [Hash<String, Object>]
        # @param header_normalizer [Proc{Object => String}]
        def initialize(headers:, header_normalizer: :to_s.to_proc)
          @headers = headers.to_h
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

      # @api private
      class Request
        include Headers

        attr_reader :verb
        attr_reader :uri

        def initialize(verb:, uri:, **header_options)
          super(**header_options)
          @verb = verb.to_s.upcase
          @uri = URI(uri)
        end

        def to_s
          [@verb, @uri.to_s].join(" ").strip
        end
      end

      # @api private
      class Response
        include Headers

        attr_reader :status

        def initialize(status:, **header_options)
          super(**header_options)
          @status = status.to_s
        end

        def redirect?
          @status.start_with?("3") && headers["location"]
        end

        def redirect_to
          URI(headers["location"]) if redirect?
        rescue URI::BadURIError
          nil
        end
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
