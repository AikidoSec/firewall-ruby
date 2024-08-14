# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    module Mysql2
      SINK = Sinks.add("mysql2", scanners: [Vulnerabilities::SQLInjectionScanner])

      module Extensions
        def query(query, *)
          SINK.scan(query: query, dialect: :mysql)

          super
        end
      end
    end
  end
end

::Mysql2::Client.prepend(Aikido::Firewall::Sinks::Mysql2::Extensions)
