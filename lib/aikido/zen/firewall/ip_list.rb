# frozen_string_literal: true

require_relative "../internals"

module Aikido::Zen
  class Firewall::IPList
    attr_reader :key
    attr_reader :source
    attr_reader :description
    attr_reader :ips

    attr_reader :ipv4_ranges
    attr_reader :ipv6_ranges

    def self.from_json(data)
      new(
        key: data["key"],
        source: data["source"],
        description: data["description"],
        ips: Array(data["ips"])
      )
    end

    def initialize(key:, source:, description:, ips:)
      @key = key
      @source = source
      @description = description

      if Internals.ip_matcher_available?
        @matcher = Internals::IPMatcher.new(ips)
        return
      end

      @ips = ips.map { |ip| IPAddr.new(ip) }
      @ipv4_ranges = []
      @ipv6_ranges = []

      @ips.each do |ip|
        range = ip.to_range
        ip_int_range = (range.begin.to_i..range.end.to_i)

        if ip.ipv4?
          @ipv4_ranges << ip_int_range
        elsif ip.ipv6?
          @ipv6_ranges << ip_int_range
        else
          raise ArgumentError, "Unsupported IP address family: #{ip.inspect}"
        end
      end

      @ipv4_ranges.sort_by!(&:begin)
      @ipv6_ranges.sort_by!(&:begin)
    end

    def inspect
      "#<#{self.class} #{@key}>"
    end

    def include?(ip)
      return native_match?(ip) if @matcher

      native_ip = nativize_ip(ip)
      return false if native_ip.nil?

      ip_int = native_ip.to_i

      if native_ip.ipv4?
        ranges_cover?(@ipv4_ranges, ip_int)
      elsif native_ip.ipv6?
        ranges_cover?(@ipv6_ranges, ip_int)
      else
        raise ArgumentError, "Unsupported IP address family: #{ip.inspect}"
      end
    end

    private

    def native_match?(ip)
      return false if ip.nil?
      unless ip.is_a?(String) || ip.is_a?(IPAddr)
        raise ArgumentError, "no explicit conversion of #{ip.class} to IPAddr"
      end

      network = ip.to_s
      return true if @matcher.include?(network)
      return false unless network.include?(":")

      parsed_ip = ip.is_a?(IPAddr) ? ip : IPAddr.new(ip)
      parsed_ip.ipv4_mapped? && @matcher.include?(parsed_ip.native.to_s)
    rescue IPAddr::InvalidAddressError
      false
    end

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

    def ranges_cover?(ranges, ip_int)
      index = ranges.bsearch_index { |range| range.begin > ip_int }
      index = index ? index - 1 : ranges.size - 1
      return false if index < 0

      ranges[index].cover?(ip_int)
    end
  end
end
