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
          self[hostname].concat(Array(addresses))
        end

        def ===(hostname)
          key?(hostname)
        end
      end
    end
  end
end
