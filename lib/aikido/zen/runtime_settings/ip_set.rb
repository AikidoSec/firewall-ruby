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
      ip = normalize_ip(ip)
      @ips.any? { |pattern| pattern === ip }
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

    def normalize_ip(ip)
      return ip unless ip.is_a?(String)

      # Handle classic IPv4-mapped IPv6 textual representation
      if ip =~ /\A::ffff:(\d{1,3}(?:\.\d{1,3}){3})\z/i
        return Regexp.last_match(1)
      end

      ip
    end
  end
end
