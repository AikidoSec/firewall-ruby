# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    # All methods that execute queries in SQLite3 initialize a Statement object,
    # so we just need to patch this method to cover all entrypoints.
    module SQLite3
      def initialize(_, sql, *)
        Vulnerabilities::SQLInjectionScanner.scan(sql, dialect: :sqlite)
        super
      end
    end
  end
end

::SQLite3::Statement.prepend(Aikido::Firewall::Sinks::SQLite3)
