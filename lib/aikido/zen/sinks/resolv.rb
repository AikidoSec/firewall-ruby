# frozen_string_literal: true

require_relative "../scanners/stored_ssrf_scanner"
require_relative "../scanners/ssrf_scanner"

module Aikido::Zen
  module Sinks
    module Resolv
      SINK = Sinks.add("resolv", scanners: [
        Scanners::StoredSSRFScanner,
        Scanners::SSRFScanner
      ])

      module Helpers
        def self.scan(name, addresses, operation)
          context = Aikido::Zen.current_context
          if context
            context["dns.lookups"] ||= Scanners::SSRF::DNSLookups.new
            context["dns.lookups"].add(name, addresses)
          end

          SINK.scan(
            hostname: name,
            addresses: addresses,
            request: context && context["ssrf.request"],
            operation: operation
          )
        end
      end

      def self.load_sinks!
        # In stdlib but not always required
        require "resolv"

        ::Resolv.class_eval do
          alias_method :each_address__internal_for_aikido_zen, :each_address

          def each_address(*args, **kwargs, &blk)
            # each_address is defined "manually" because no sink method pattern
            # is applicable.

            name, = args

            addresses = []
            each_address__internal_for_aikido_zen(*args, **kwargs) do |address|
              addresses << address
              blk.call(address)
            end
          ensure
            # Ensure partial results are scanned.

            Sinks::DSL.safe do
              Helpers.scan(name, addresses, "lookup")
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Resolv.load_sinks!
