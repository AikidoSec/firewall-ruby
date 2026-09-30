# frozen_string_literal: true

require_relative "../internals"

module Aikido::Zen
  class Firewall::IPList
    attr_reader :key
    attr_reader :source
    attr_reader :description

    def self.from_json(data)
      new(
        key: data["key"],
        source: data["source"],
        description: data["description"],
        ips: Array(data["ips"])
      )
    end

    # @param ips [Array<String>] IP addresses or networks in CIDR notation.
    # @param max_rejected_count [Integer] how many invalid networks to tolerate.
    #   By default any invalid network is an error.
    # @raise [ArgumentError] if more than +max_rejected_count+ networks are invalid.
    def initialize(key:, source:, description:, ips:, max_rejected_count: 0)
      @key = key
      @source = source
      @description = description
      @ips = Internals::IPMatcher.new(ips)

      if @ips.rejected_count > max_rejected_count
        raise ArgumentError, "IP list #{key.inspect} has #{@ips.rejected_count} invalid network(s), more than the #{max_rejected_count} allowed"
      end
    end

    def inspect
      "#<#{self.class} #{@key}>"
    end

    # @param ip [String, nil] an IP address.
    # @return [Boolean] whether the address is in any of the covered networks.
    def include?(ip)
      return false if ip.nil?

      @ips.include?(ip)
    end
  end
end
