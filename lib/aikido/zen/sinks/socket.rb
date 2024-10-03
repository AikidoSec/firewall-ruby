# frozen_string_literal: true

require "socket"

module Aikido::Zen
  module Sinks
    # We intercept IPSocket.open to hook our DNS checks around it, since
    # there's no way to access the internal DNS resolution that happens in C
    # when using the socket primitives.
    module Socket
      SINK = Sinks.add("socket", scanners: [
        Aikido::Zen::Scanners::StoredSSRFScanner,
        Aikido::Zen::Scanners::SSRFScanner
      ])

      module IPSocketExtensions
        def self.scan_socket(hostname, socket)
          # ["AF_INET", 80, "10.0.0.1", "10.0.0.1"]
          addr_family, *, remote_address = socket.peeraddr

          # We only care about IPv4 (AF_INET) or IPv6 (AF_INET6) sockets
          # This might be overcautious, since this is _IP_Socket, so you
          # would expect it's only used for IP connections?
          return unless addr_family.start_with?("AF_INET")

          if (context = Aikido::Zen.current_context)
            context["dns.lookups"] ||= Aikido::Zen::Scanners::SSRF::DNSLookups.new
            context["dns.lookups"].add(hostname, remote_address)
          end

          SINK.scan(
            hostname: hostname,
            addresses: [remote_address],
            request: context && context["ssrf.request"],
            operation: "open"
          )
        end

        def open(name, *)
          socket = super

          IPSocketExtensions.scan_socket(name, socket)

          socket
        end
      end
    end
  end
end

::IPSocket.singleton_class.prepend(Aikido::Zen::Sinks::Socket::IPSocketExtensions)
