# frozen_string_literal: true

require "ipaddr"

module Aikido::Zen
  # Models a list of IP addresses or CIDR blocks, where we can check if a given
  # address is part of any of the members.
  class RuntimeSettings::IPSet
    def self.from_json(ips)
      new(Array(ips).map { |ip| IPAddr.new(ip) })
    end

    def initialize(ips = Set.new)
      @ips = ips.to_set
    end

    def empty?
      @ips.empty?
    end

    def include?(ip)
      native_ip = nativize_ip(ip)
      @ips.any? { |pattern| pattern === native_ip }
    end
    alias_method :===, :include?

    def ==(other)
      other.is_a?(RuntimeSettings::IPSet) && to_set == other.to_set
    end

    protected

    def to_set
      @ips
    end

    private

    def nativize_ip(ip)
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
  end
end
