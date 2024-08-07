# frozen_string_literal: true

module Aikido::Firewall
  module Sinks
    module PG
      %w[
        send_query exec sync_exec async_exec
        send_query_params exec_params sync_exec_params async_exec_params
      ].each do |method|
        module_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{method}(query, *)
            Vulnerabilities::SQLInjectionScanner.scan(query, dialect: :postgresql)
            super
          end
        RUBY
      end

      %w[
        send_prepare prepare async_prepare sync_prepare
      ].each do |method|
        module_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{method}(_, query, *)
            Vulnerabilities::SQLInjectionScanner.scan(query, dialect: :postgresql)
            super
          end
        RUBY
      end
    end
  end
end

::PG::Connection.prepend(Aikido::Firewall::Sinks::PG)
