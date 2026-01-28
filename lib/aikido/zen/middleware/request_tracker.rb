# frozen_string_literal: true

module Aikido::Zen
  module Middleware
    # Rack middleware used to track request
    # It implements the logic under that which is considered worthy of being tracked.
    class RequestTracker
      def initialize(app, settings: Aikido::Zen.runtime_settings)
        @app = app
        @settings = settings
      end

      def call(env)
        request = Aikido::Zen::Middleware.request_from(env)
        response = @app.call(env)

        if request.route && track?(
          status_code: response[0],
          route: request.route.path,
          http_method: request.request_method,
          ip: request.ip
        )
          Aikido::Zen.track_request(request)

          if Aikido::Zen.config.collect_api_schema?
            Aikido::Zen.track_discovered_route(request)
          end
        end

        response
      end

      IGNORED_METHODS = %w[OPTIONS HEAD]
      IGNORED_EXTENSIONS = %w[properties config webmanifest]
      IGNORED_SEGMENTS = ["cgi-bin"]
      WELL_KNOWN_URIS = %w[
        /.well-known/acme-challenge
        /.well-known/amphtml
        /.well-known/api-catalog
        /.well-known/appspecific
        /.well-known/ashrae
        /.well-known/assetlinks.json
        /.well-known/broadband-labels
        /.well-known/brski
        /.well-known/caldav
        /.well-known/carddav
        /.well-known/change-password
        /.well-known/cmp
        /.well-known/coap
        /.well-known/coap-eap
        /.well-known/core
        /.well-known/csaf
        /.well-known/csaf-aggregator
        /.well-known/csvm
        /.well-known/did.json
        /.well-known/did-configuration.json
        /.well-known/dnt
        /.well-known/dnt-policy.txt
        /.well-known/dots
        /.well-known/ecips
        /.well-known/edhoc
        /.well-known/enterprise-network-security
        /.well-known/enterprise-transport-security
        /.well-known/est
        /.well-known/genid
        /.well-known/gnap-as-rs
        /.well-known/gpc.json
        /.well-known/gs1resolver
        /.well-known/hoba
        /.well-known/host-meta
        /.well-known/host-meta.json
        /.well-known/hosting-provider
        /.well-known/http-opportunistic
        /.well-known/idp-proxy
        /.well-known/jmap
        /.well-known/keybase.txt
        /.well-known/knx
        /.well-known/looking-glass
        /.well-known/masque
        /.well-known/matrix
        /.well-known/mercure
        /.well-known/mta-sts.txt
        /.well-known/mud
        /.well-known/nfv-oauth-server-configuration
        /.well-known/ni
        /.well-known/nodeinfo
        /.well-known/nostr.json
        /.well-known/oauth-authorization-server
        /.well-known/oauth-protected-resource
        /.well-known/ohttp-gateway
        /.well-known/openid-federation
        /.well-known/open-resource-discovery
        /.well-known/openid-configuration
        /.well-known/openorg
        /.well-known/oslc
        /.well-known/pki-validation
        /.well-known/posh
        /.well-known/privacy-sandbox-attestations.json
        /.well-known/private-token-issuer-directory
        /.well-known/probing.txt
        /.well-known/pvd
        /.well-known/rd
        /.well-known/related-website-set.json
        /.well-known/reload-config
        /.well-known/repute-template
        /.well-known/resourcesync
        /.well-known/sbom
        /.well-known/security.txt
        /.well-known/ssf-configuration
        /.well-known/sshfp
        /.well-known/stun-key
        /.well-known/terraform.json
        /.well-known/thread
        /.well-known/time
        /.well-known/timezone
        /.well-known/tdmrep.json
        /.well-known/tor-relay
        /.well-known/tpcd
        /.well-known/traffic-advice
        /.well-known/trust.txt
        /.well-known/uma2-configuration
        /.well-known/void
        /.well-known/webfinger
        /.well-known/webweaver.json
        /.well-known/wot
      ]

      # @param status_code [Integer]
      # @param route [String]
      # @param http_method [String]
      def track?(status_code:, route:, http_method:, ip: nil)
        # Bypass for allowed IPs
        return false if @settings.allowed_ips.include?(ip)

        # In the UI we want to show only successful (2xx) or redirect (3xx) responses
        # anything else is discarded.
        return false unless status_code >= 200 && status_code <= 399

        return false if IGNORED_METHODS.include?(http_method)

        segments = route.split "/"

        # Do not discover routes with dot files like `/path/to/.file` or `/.directory/file`
        # We want to allow discovery of well-known URIs like `/.well-known/acme-challenge`
        return false if segments.any? { |s| is_dot_file s } && !is_well_known_uri(route)

        return false if segments.any? { |s| contains_ignored_string s }

        # Check for every file segment if it contains a file extension and if it
        # should be discovered or ignored
        segments.all? { |s| should_track_extension s }
      end

      private

      # Check if a path is a well-known URI
      # e.g. /.well-known/acme-challenge
      # https://www.iana.org/assignments/well-known-uris/well-known-uris.xhtml
      def is_well_known_uri(route)
        WELL_KNOWN_URIS.include?(route)
      end

      def is_dot_file(segment)
        segment.start_with?(".") && segment.size > 1
      end

      def contains_ignored_string(segment)
        IGNORED_SEGMENTS.any? { |ignored| segment.include?(ignored) }
      end

      # Ignore routes which contain file extensions
      def should_track_extension(segment)
        extension = get_file_extension(segment)

        return true unless extension

        # Do not discover files with extensions of 1 to 5 characters,
        # e.g. file.css, file.js, file.woff2
        return false if extension.size > 1 && extension.size < 6

        # Ignore some file extensions that are longer than 5 characters or shorter than 2 chars
        return false if IGNORED_EXTENSIONS.include?(extension)

        true
      end

      def get_file_extension(segment)
        extension = File.extname(segment)
        if extension&.start_with?(".")
          # Remove the dot from the extension
          return extension[1..]
        end
        extension
      end
    end
  end
end
