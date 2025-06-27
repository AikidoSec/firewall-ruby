# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module Mysql2
      def self.load_sinks!
        ::Mysql2::Client.prepend(ClientExtensions)
      end

      SINK = Sinks.add("mysql2", scanners: [Scanners::SQLInjectionScanner])

      module Helpers
        def self.scan(query, operation)
          SINK.scan(query: query, dialect: :mysql, operation: operation)
        end
      end

      module ClientExtensions
        extend Sinks::DSL

        sink_before :query do |sql|
          Helpers.scan(sql, "query")
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Mysql2.load_sinks!
