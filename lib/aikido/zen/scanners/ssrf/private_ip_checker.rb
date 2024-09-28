# frozen_string_literal: true

require "resolv"
require "ipaddr"

module Aikido::Zen
  module Scanners
    module SSRF
      # Little helper to check if a given address is either an obvious local
      # address (127.0.0.1, ::1, etc), in one of the "special-use" IP ranges
      # as per RFCs 5735 (which goes beyond the "normal" private ranges defined
      # in RFC 1918: 10.0.0.0/8, 127.16.0.0/12, 192.168.0.0/16) or RFC 4193
      # (fc00::/7).
      #
      # If instead of given an address it's given a hostname, it will try to
      # resolve it against the local hosts file (i.e. /etc/hosts). If it
      # resolves to an address, it will check if that is a "private" address.
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

        def resolve(hostname_or_address)
          case hostname_or_address
          when Resolv::AddressRegex
            [IPAddr.new(hostname_or_address)]
          else
            @resolver.getaddresses(hostname_or_address.to_s)
              .map { |address| IPAddr.new(address) }
          end
        end
      end
    end
  end
end
