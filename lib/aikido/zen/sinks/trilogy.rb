# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module Trilogy
      SINK = Sinks.add("trilogy", scanners: [Scanners::SQLInjectionScanner])

      module Helpers
        def self.scan(query, operation)
          SINK.scan(query: query, dialect: :mysql, operation: operation)
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "trilogy", ">= 2.0"
          require "trilogy"

          ::Trilogy.class_eval do
            extend Sinks::DSL

            presafe_sink_before :query do |sql|
              Sinks::DSL.safe do
                Helpers.scan(sql, "query")
              end

              Aikido::Zen.idor_protect(sql, :mysql)
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Trilogy.load_sinks!
