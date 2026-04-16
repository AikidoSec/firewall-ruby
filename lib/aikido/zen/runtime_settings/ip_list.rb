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
        ips: RuntimeSettings::IPSet.from_json(data["ips"])
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
      @ips.include?(ip)
    end
  end
end
