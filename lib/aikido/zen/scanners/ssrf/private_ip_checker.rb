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
            ip.loopback? || ip.private? || RFC5735.any? { |range| range === ip }
          end
        end

        private

        RFC5735 = [
          IPAddr.new("0.0.0.0/8"),
          IPAddr.new("100.64.0.0/10"),
          IPAddr.new("127.0.0.0/8"),
          IPAddr.new("169.254.0.0/16"),
          IPAddr.new("192.0.0.0/24"),
          IPAddr.new("192.0.2.0/24"),
          IPAddr.new("192.31.196.0/24"),
          IPAddr.new("192.52.193.0/24"),
          IPAddr.new("192.88.99.0/24"),
          IPAddr.new("192.175.48.0/24"),
          IPAddr.new("198.18.0.0/15"),
          IPAddr.new("198.51.100.0/24"),
          IPAddr.new("203.0.113.0/24"),
          IPAddr.new("240.0.0.0/4"),
          IPAddr.new("224.0.0.0/4"),
          IPAddr.new("255.255.255.255/32"),

          IPAddr.new("::/128"),              # Unspecified address
          IPAddr.new("fe80::/10"),           # Link-local address (LLA)
          IPAddr.new("::ffff:127.0.0.1/128") # IPv4-mapped address
        ]

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
