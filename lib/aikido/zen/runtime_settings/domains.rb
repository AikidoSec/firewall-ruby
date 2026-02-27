# frozen_string_literal: true

require_relative "domain_settings"

module Aikido::Zen
  class RuntimeSettings::Domains
    def self.from_json(data)
      domain_pairs = Array(data).map do |value|
        hostname = value["hostname"].downcase
        settings = RuntimeSettings::DomainSettings.from_json(value)
        [hostname, settings]
      end

      new(domain_pairs.to_h)
    end

    def initialize(domains = {})
      @domains = domains
      @domains.default = RuntimeSettings::DomainSettings.none
    end

    def [](hostname)
      @domains[hostname.downcase]
    end

    def include?(hostname)
      @domains.key?(hostname.downcase)
    end

    def size
      @domains.size
    end
  end
end
