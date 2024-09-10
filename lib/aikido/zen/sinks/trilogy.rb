# frozen_string_literal: true

require_relative "../sink"

module Aikido::Zen
  module Sinks
    module Trilogy
      SINK = Sinks.add("trilogy", scanners: [Scanners::SQLInjectionScanner])

      module Extensions
        def query(query, *)
          SINK.scan(query: query, dialect: :mysql, operation: "query")

          super
        end
      end
    end
  end
end

::Trilogy.prepend(Aikido::Zen::Sinks::Trilogy::Extensions)
