# frozen_string_literal: true

require_relative "../sink"

module Aikido::Zen
  module Sinks
    module Mysql2
      SINK = Sinks.add("mysql2", scanners: [Scanners::SQLInjectionScanner])

      module Extensions
        def query(query, *)
          SINK.scan(query: query, dialect: :mysql, operation: "query")

          super
        end
      end
    end
  end
end

::Mysql2::Client.prepend(Aikido::Zen::Sinks::Mysql2::Extensions)
