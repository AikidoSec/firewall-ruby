# frozen_string_literal: true

require_relative "domain_settings"
require "simpleidn"

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
      @domains[normalize(hostname)]
    end

    def include?(hostname)
      @domains.key?(normalize(hostname))
    end

    def size
      @domains.size
    end

    private

    def normalize(hostname)
      SimpleIDN.to_unicode(hostname).downcase
    end
  end
end
