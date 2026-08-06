# frozen_string_literal: true

module Aikido::Zen
  module IPLists
    # An IP address resolved to the family and unsigned integer
    # representation used to look it up against a `Data::IPList`.
    class Address
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

    # @param ip [IPAddr, String, nil]
    # @return [Address, nil] +nil+ if +ip+ is +nil+ or can't be parsed as an
    #   IP address
    # @raise [ArgumentError] if +ip+ isn't an IPAddr, String, or nil
    def self.parse_ip(ip)
      native_ip = nativize(ip)
      return nil if native_ip.nil?

      if native_ip.ipv4?
        Address.new(:ipv4, native_ip.to_i)
      elsif native_ip.ipv6?
        Address.new(:ipv6, native_ip.to_i)
      else
        raise ArgumentError, "Unsupported IP address family: #{ip.inspect}"
      end
    end

    def self.nativize(ip)
      case ip
      when IPAddr
        ip.native
      when String
        begin
          IPAddr.new(ip).native
        rescue IPAddr::InvalidAddressError
          nil
        end
      when nil
        nil
      else
        raise ArgumentError, "no explicit conversion of #{ip.class} to IPAddr"
      end
    end
    private_class_method :nativize
  end
end
