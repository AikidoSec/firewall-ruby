# frozen_string_literal: true

module Aikido::Zen
  class IPLists
    class Address
      # @param ip [IPAddr, String, nil]
      # @return [Aikido::Zen::IPLists::Address, nil] `nil` if `ip` is `nil` or can not be parsed
      # @raise [ArgumentError] if `ip` is not an IPAddr, String, or nil
      def self.parse(ip)
        native_ip = Helpers.nativize_ip(ip)
        return nil if native_ip.nil?

        if native_ip.ipv4?
          new(:ipv4, native_ip.to_i)
        elsif native_ip.ipv6?
          new(:ipv6, native_ip.to_i)
        else
          raise ArgumentError, "unsupported IP address family: #{ip.inspect}"
        end
      end

      # @return [:ipv4, :ipv6]
      attr_reader :family

      # @param family [:ipv4, :ipv6]
      # @param ip_int [Integer]
      def initialize(family, ip_int)
        @family = family
        @ip_int = ip_int
      end

      # @return [Integer]
      def to_i
        @ip_int
      end
    end
  end
end
