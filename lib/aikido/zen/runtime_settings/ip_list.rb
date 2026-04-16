# frozen_string_literal: true

module Aikido::Zen
  class RuntimeSettings::IPList
    attr_reader :key
    attr_reader :source
    attr_reader :description
    attr_reader :ips

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
    end

    def inspect
      "#<#{self.class} #{@key}>"
    end

    def include?(ip)
      native_ip = nativize_ip(ip)
      return false if native_ip.nil?

      @ips.any? { |pattern| pattern === native_ip }
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
