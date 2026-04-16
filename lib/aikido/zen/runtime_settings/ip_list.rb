# frozen_string_literal: true

module Aikido::Zen
  class RuntimeSettings::IPList
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
        ips: Array(data["ips"]).map { |ip| IPAddr.new(ip) }
      )
    end

    def initialize(key:, source:, description:, ips:)
      @key = key
      @source = source
      @description = description
      @ips = ips

      @ipv4_ranges = []
      @ipv6_ranges = []

      ips.each do |ip|
        if ip.ipv4?
          @ipv4_ranges << ip.to_range
        elsif ip.ipv6?
          @ipv6_ranges << ip.to_range
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
      native_ip = nativize_ip(ip)
      return false if native_ip.nil?

      if native_ip.ipv4?
        ranges_cover?(@ipv4_ranges, native_ip)
      elsif native_ip.ipv6?
        ranges_cover?(@ipv6_ranges, native_ip)
      else
        raise ArgumentError, "Unsupported IP address family: #{ip.inspect}"
      end
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

    def ranges_cover?(ranges, ip)
      index = ranges.bsearch_index { |range| range.begin > ip }
      index = index ? index - 1 : ranges.size - 1
      return false if index < 0

      ranges[index].cover?(ip)
    end
  end
end
