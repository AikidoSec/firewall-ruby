# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    module SQLite3
      module Database
        def exec_batch(sql, *)
          Vulnerabilities::SQLInjectionScanner.scan(sql, dialect: :sqlite)
          super
        end
      end

      module Statement
        def initialize(_, sql, *)
          Vulnerabilities::SQLInjectionScanner.scan(sql, dialect: :sqlite)
          super
        end
      end
    end
  end
end

::SQLite3::Database.prepend(Aikido::Firewall::Sinks::SQLite3::Database)
::SQLite3::Statement.prepend(Aikido::Firewall::Sinks::SQLite3::Statement)
