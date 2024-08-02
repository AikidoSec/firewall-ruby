# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    module Mysql2
      def query(query, *)
        Vulnerabilities::SQLInjectionScanner.scan(query)

        super
      end
    end
  end
end

::Mysql2::Client.prepend(Aikido::Firewall::Sinks::Mysql2)
