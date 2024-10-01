# frozen_string_literal: true

require_relative "../sink"
require_relative "../scanners/stored_ssrf_scanner"

module Aikido::Zen
  module Sinks
    module Resolv
      SINK = Sinks.add("resolv", scanners: [
        Aikido::Zen::Scanners::StoredSSRFScanner
      ])

      module Extensions
        def each_address(name, &block)
          addresses = []

          super do |address|
            addresses << address
            yield address
          end
        ensure
          SINK.scan(hostname: name, addresses: addresses, operation: "lookup")
        end
      end
    end
  end
end

::Resolv.prepend(Aikido::Zen::Sinks::Resolv::Extensions)
