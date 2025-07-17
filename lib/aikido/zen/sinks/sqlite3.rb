# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module SQLite3
      def self.load_sinks!
        if Gem.loaded_specs["sqlite3"]
          require "sqlite3"

          ::SQLite3::Database.prepend(DatabaseExtensions)
          ::SQLite3::Statement.prepend(StatementExtensions)
        end
      end

      SINK = Sinks.add("sqlite3", scanners: [Scanners::SQLInjectionScanner])

      module Helpers
        def self.scan(query, operation)
          SINK.scan(
            query: query,
            dialect: :sqlite,
            operation: operation
          )
        end
      end

      module DatabaseExtensions
        extend Sinks::DSL

        private

        # SQLite3::Database#exec_batch is an internal native private method.
        sink_before :exec_batch do |sql|
          Helpers.scan(sql, "exec_batch")
        end
      end

      module StatementExtensions
        extend Sinks::DSL

        sink_before :initialize do |_db, sql|
          Helpers.scan(sql, "statement.execute")
        end
      end
    end
  end
end

Aikido::Zen::Sinks::SQLite3.load_sinks!
