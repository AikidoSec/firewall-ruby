# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    module Trilogy
      def query(query, *)
        Vulnerabilities::SQLInjectionScanner.scan(query, dialect: :mysql)

        super
      end
    end
  end
end

::Trilogy.prepend(Aikido::Firewall::Sinks::Trilogy)
