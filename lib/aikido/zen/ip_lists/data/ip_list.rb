# frozen_string_literal: true

require_relative "ip_list/writer"
require_relative "ip_list/reader"
require_relative "../address"

module Aikido::Zen
  module IPLists
    module Data
      # A pair of ipv4/ipv6 `Reader`s for the same logical IP list,
      # dispatching #include? to whichever one matches the given address.
      #
      # Takes already-built Readers -- an IPList never opens, owns, or
      # knows anything about where its data lives, so there's nothing here
      # to close.
      #
      # Not thread-safe: give each thread its own IPList, or synchronize
      # access to a shared one yourself.
      class IPList
        # @param ipv4_reader [Reader]
        # @param ipv6_reader [Reader]
        def initialize(ipv4_reader:, ipv6_reader:)
          @readers = {ipv4: ipv4_reader, ipv6: ipv6_reader}
        end

        # @param ip [IPAddr, String, nil]
        # @return [Boolean]
        def include?(ip)
          address = IPLists.parse_ip(ip)
          return false if address.nil?

          @readers.fetch(address.family).include?(address.to_i)
        end
      end
    end
  end
end
