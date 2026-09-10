# frozen_string_literal: true

require_relative "ip_matcher"

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

    def initialize(key:, source:, description:, ips:)
      @key = key
      @source = source
      @description = description
      @matcher = Firewall::IPMatcher.new(ips)
    end

    def inspect
      "#<#{self.class} #{@key}>"
    end

    def include?(ip)
      @matcher.include_with_mapped?(ip)
    end

    def size
      @matcher.size
    end
  end
end
