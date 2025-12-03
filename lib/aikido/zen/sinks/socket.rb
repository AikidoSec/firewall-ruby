# frozen_string_literal: true

require "socket"
require_relative "../scanners/stored_ssrf_scanner"
require_relative "../scanners/ssrf_scanner"

module Aikido::Zen
  module Sinks
    # We intercept IPSocket.open to hook our DNS checks around it, since
    # there's no way to access the internal DNS resolution that happens in C
    # when using the socket primitives.
    module Socket
      SINK = Sinks.add("socket", scanners: [
        Scanners::StoredSSRFScanner,
        Scanners::SSRFScanner
      ])

      module Helpers
        def self.scan(hostname, socket, operation)
          # We're patching IPSocket.open(..) method.
          # The IPSocket class hierarchy is:
          #             IPSocket
          #            /        \
          #       TCPSocket    UDPSocket
          #       /       \
          # TCPServer     SOCKSSocket
          #
          # Because we want to scan only HTTP requests, we skip in case the
          # socket is not *exactly* an instance of TCPSocket — it's any
          # of it subclasses
          return unless socket.instance_of?(TCPSocket)

          # ["AF_INET", 80, "10.0.0.1", "10.0.0.1"]
          address_family, _port, _hostname, numeric_address = socket.peeraddr(:numeric)

          # We only care about IPv4 (AF_INET) or IPv6 (AF_INET6) sockets
          # This might be overcautious, since this is _IP_Socket, so you
          # would expect it's only used for IP connections?

          # Code coverage is disabled here because the then clause is a no-op,
          # so there is nothing to cover.
          # :nocov:
          return unless address_family.start_with?("AF_INET")
          # :nocov:

          context = Aikido::Zen.current_context
          if context
            context["dns.lookups"] ||= Scanners::SSRF::DNSLookups.new
            context["dns.lookups"].add(hostname, numeric_address)
          end

          SINK.scan(
            hostname: hostname,
            addresses: [numeric_address],
            request: context && context["ssrf.request"],
            operation: operation
          )
        end
      end

      def self.load_sinks!
        ::IPSocket.singleton_class.class_eval do
          extend Sinks::DSL

          sink_after :open do |socket, remote_host|
            # Code coverage is disabled here because the tests are contrived and
            # intentionally do not call open.
            # :nocov:
            Helpers.scan(remote_host, socket, "open")
            # :nocov:
          rescue
            # If the scan raises an exception (e.g., stored SSRF detected),
            # we must close the socket to avoid resource leaks.
            socket.close

            raise
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Socket.load_sinks!
