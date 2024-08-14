# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    module Trilogy
      SINK = Sinks.add("trilogy", scanners: [Vulnerabilities::SQLInjectionScanner])

      module Extensions
        def query(query, *)
          SINK.scan(query: query, dialect: :mysql)

          super
        end
      end
    end
  end
end

::Trilogy.prepend(Aikido::Firewall::Sinks::Trilogy::Extensions)
