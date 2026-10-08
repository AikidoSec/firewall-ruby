# frozen_string_literal: true

require "delegate"

module Aikido::Zen
  module Scanners
    module SSRF
      # Simple per-request cache of all DNS lookups performed for a given host.
      # We can store this in the context after performing a lookup, and have the
      # SSRF scanner make sure the hostname being inspected doesn't actually
      # resolve to an internal/dangerous IP.
      class DNSLookups < SimpleDelegator
        def initialize
          super(Hash.new { |h, k| h[k] = [] })
        end

        def add(hostname, addresses)
          self[normalize_hostname(hostname)].concat(Array(addresses))
        end

        def ===(hostname)
          key?(normalize_hostname(hostname))
        end

        def [](hostname)
          super(normalize_hostname(hostname))
        end

        private

        # Normalizes a hostname to ensure DNS-equivalent spellings match.
        # DNS hostnames are case-insensitive and trailing dots are equivalent.
        #
        # @param hostname [String, nil]
        # @return [String, nil]
        def normalize_hostname(hostname)
          return hostname if hostname.nil?

          normalized = hostname.to_s.downcase
          normalized = normalized.chomp(".") if normalized.end_with?(".")
          normalized
        end
      end
    end
  end
end
