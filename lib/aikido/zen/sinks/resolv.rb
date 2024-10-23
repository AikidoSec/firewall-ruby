# frozen_string_literal: true

require_relative "../sink"
require_relative "../scanners/stored_ssrf_scanner"
require_relative "../scanners/ssrf_scanner"

module Aikido::Zen
  module Sinks
    module Resolv
      SINK = Sinks.add("resolv", scanners: [
        Aikido::Zen::Scanners::StoredSSRFScanner,
        Aikido::Zen::Scanners::SSRFScanner
      ])

      module Extensions
        def each_address(name, &block)
          addresses = []

          super do |address|
            addresses << address
            yield address
          end
        ensure
          if (context = Aikido::Zen.current_context)
            context["dns.lookups"] ||= Aikido::Zen::Scanners::SSRF::DNSLookups.new
            context["dns.lookups"].add(name, addresses)
          end

          SINK.scan(
            hostname: name,
            addresses: addresses,
            request: context && context["ssrf.request"],
            operation: "lookup"
          )
        end
      end
    end
  end
end

::Resolv.prepend(Aikido::Zen::Sinks::Resolv::Extensions)
