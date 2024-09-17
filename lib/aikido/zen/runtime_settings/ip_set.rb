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
  end
end
