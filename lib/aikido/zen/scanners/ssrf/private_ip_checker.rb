# frozen_string_literal: true

require "resolv"
require "ipaddr"

module Aikido::Zen
  module Scanners
    module SSRF
      # Little helper to check if a given hostname or address is to be
      # considered "dangerous" when used for an outbound HTTP request.
      #
      # When given a hostname:
      #
      # * If any DNS lookups have been performed and stored in the current Zen
      #   context (under the "dns.lookups" metadata key), we will map it to the
      #   list of IPs that we've resolved it to.
      #
      # * If not, we'll still try to map it to any statically defined address in
      #   the system hosts file (e.g. /etc/hosts).
      #
      # Once we mapped the hostname to an IP address (or, if given an IP
      # address), this will check that it's not a loopback address, a private IP
      # address (as defined by RFCs 1918 and 4193), or in one of the
      # "special-use" IP ranges defined in RFC 5735.
      class PrivateIPChecker
        def initialize(resolver = Resolv::Hosts.new)
          @resolver = resolver
        end

        # @param hostname_or_address [String]
        # @return [Boolean]
        def private?(hostname_or_address)
          resolve(hostname_or_address).any? do |ip|
            PRIVATE_RANGES.any? { |range| range === ip }
          end
        end

        private

        PRIVATE_IPV4_RANGES = [
          IPAddr.new("0.0.0.0/8"),         # "This" network (RFC 1122)
          IPAddr.new("10.0.0.0/8"),        # Private-Use Networks (RFC 1918)
          IPAddr.new("100.64.0.0/10"),     # Shared Address Space (RFC 6598)
          IPAddr.new("127.0.0.0/8"),       # Loopback (RFC 1122)
          IPAddr.new("169.254.0.0/16"),    # Link Local (RFC 3927)
          IPAddr.new("172.16.0.0/12"),     # Private-Use Networks (RFC 1918)
          IPAddr.new("192.0.0.0/24"),      # IETF Protocol Assignments (RFC 5736)
          IPAddr.new("192.0.2.0/24"),      # TEST-NET-1 (RFC 5737)
          IPAddr.new("192.31.196.0/24"),   # AS112 Redirection Anycast (RFC 7535)
          IPAddr.new("192.52.193.0/24"),   # Automatic Multicast Tunneling (RFC 7450)
          IPAddr.new("192.88.99.0/24"),    # 6to4 Relay Anycast (RFC 3068)
          IPAddr.new("192.168.0.0/16"),    # Private-Use Networks (RFC 1918)
          IPAddr.new("192.175.48.0/24"),   # AS112 Redirection Anycast (RFC 7535)
          IPAddr.new("198.18.0.0/15"),     # Network Interconnect Device Benchmark Testing (RFC 2544)
          IPAddr.new("198.51.100.0/24"),   # TEST-NET-2 (RFC 5737)
          IPAddr.new("203.0.113.0/24"),    # TEST-NET-3 (RFC 5737)
          IPAddr.new("224.0.0.0/4"),       # Multicast (RFC 3171)
          IPAddr.new("240.0.0.0/4"),       # Reserved for Future Use (RFC 1112)
          IPAddr.new("255.255.255.255/32") # Limited Broadcast (RFC 919)
        ]

        PRIVATE_IPV6_RANGES = [
          IPAddr.new("::/128"),            # Unspecified address (RFC 4291)
          IPAddr.new("::1/128"),           # Loopback address (RFC 4291)
          IPAddr.new("fc00::/7"),          # Unique local address (ULA) (RFC 4193
          IPAddr.new("fe80::/10"),         # Link-local address (LLA) (RFC 4291)
          IPAddr.new("100::/64"),          # Discard prefix (RFC 6666)
          IPAddr.new("2001:db8::/32"),     # Documentation prefix (RFC 3849)
          IPAddr.new("3fff::/20")          # Documentation prefix (RFC 9637)
        ]

        PRIVATE_RANGES = PRIVATE_IPV4_RANGES + PRIVATE_IPV6_RANGES + PRIVATE_IPV4_RANGES.map(&:ipv4_mapped)

        def resolved_in_current_context
          context = Aikido::Zen.current_context
          context && context["dns.lookups"]
        end

        def resolve(hostname_or_address)
          return [] if hostname_or_address.nil?

          case hostname_or_address
          when Resolv::AddressRegex
            [IPAddr.new(hostname_or_address)]
          when resolved_in_current_context
            resolved_in_current_context[hostname_or_address]
              .map { |address| IPAddr.new(address) }
          else
            @resolver.getaddresses(hostname_or_address.to_s)
              .map { |address| IPAddr.new(address) }
          end
        end
      end
    end
  end
end
