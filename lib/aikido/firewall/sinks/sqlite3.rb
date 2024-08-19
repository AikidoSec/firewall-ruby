# frozen_string_literal: true

require_relative "../sink"

module Aikido::Firewall
  module Sinks
    module SQLite3
      SINK = Sinks.add("sqlite3", scanners: [Vulnerabilities::SQLInjectionScanner])

      module DatabaseExt
        def exec_batch(sql, *)
          SINK.scan(query: sql, dialect: :sqlite, operation: "exec_batch")

          super
        end
      end

      module StatementExt
        def initialize(_, sql, *)
          SINK.scan(query: sql, dialect: :sqlite, operation: "statement.execute")

          super
        end
      end
    end
  end
end

::SQLite3::Database.prepend(Aikido::Firewall::Sinks::SQLite3::DatabaseExt)
::SQLite3::Statement.prepend(Aikido::Firewall::Sinks::SQLite3::StatementExt)
