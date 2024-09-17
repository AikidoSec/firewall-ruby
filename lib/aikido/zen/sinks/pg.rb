# frozen_string_literal: true

require_relative "../sink"

module Aikido::Zen
  module Sinks
    module PG
      SINK = Sinks.add("pg", scanners: [Scanners::SQLInjectionScanner])

      module Extensions
        %i[
          send_query exec sync_exec async_exec
          send_query_params exec_params sync_exec_params async_exec_params
        ].each do |method|
          module_eval <<~RUBY, __FILE__, __LINE__ + 1
            def #{method}(query, *)
              SINK.scan(query: query, dialect: :postgresql, operation: :#{method})
              super
            rescue Aikido::Zen::SQLInjectionError
              # The pg adapter does not wrap exceptions in StatementInvalid, which
              # leads to inconsistent handling. This guarantees that all Aikido
              # errors are wrapped in a StatementInvalid, so documentation can be
              # consistent.
              raise ActiveRecord::StatementInvalid
            end
          RUBY
        end

        %i[
          send_prepare prepare async_prepare sync_prepare
        ].each do |method|
          module_eval <<~RUBY, __FILE__, __LINE__ + 1
            def #{method}(_, query, *)
              SINK.scan(query: query, dialect: :postgresql, operation: :#{method})
              super
            rescue Aikido::Zen::SQLInjectionError
              # The pg adapter does not wrap exceptions in StatementInvalid, which
              # leads to inconsistent handling. This guarantees that all Aikido
              # errors are wrapped in a StatementInvalid, so documentation can be
              # consistent.
              raise ActiveRecord::StatementInvalid
            end
          RUBY
        end
      end
    end
  end
end

::PG::Connection.prepend(Aikido::Zen::Sinks::PG::Extensions)
