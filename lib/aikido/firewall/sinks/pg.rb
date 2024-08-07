# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    module PG
      [:sync_exec, :async_exec, :exec, :exec_params, :sync_exec_prepared, :sync_exec_params, :exec_prepared, :async_exec_prepared, :async_exec_params].each do |method|
        module_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{method}(query, *)
            Vulnerabilities::SQLInjectionScanner.scan(query, dialect: :postgresql)
            super
          end
        RUBY
      end
    end
  end
end

::PG::Connection.prepend(Aikido::Firewall::Sinks::PG)
