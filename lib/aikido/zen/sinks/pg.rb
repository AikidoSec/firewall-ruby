# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module PG
      SINK = Sinks.add("pg", scanners: [Scanners::SQLInjectionScanner])

      module Helpers
        # For some reason, the ActiveRecord pg adaptor does not wrap exceptions
        # in ActiveRecord::StatementInvalid, leading to inconsistent handling.
        # This guarantees that Aikido::Zen::SQLInjectionErrors are wrapped in
        # an ActiveRecord::StatementInvalid.
        def self.safe(&block)
          # Code coverage is disabled here because this ActiveRecord behavior is
          # exercised in end-to-end tests, which are not covered by SimpleCov.
          # :nocov:
          if !defined?(ActiveRecord::StatementInvalid)
            Sinks::DSL.safe(&block)
          else
            begin
              Sinks::DSL.safe(&block)
            rescue Aikido::Zen::SQLInjectionError => err
              raise ActiveRecord::StatementInvalid, cause: err
            end
          end
          # :nocov:
        end

        def self.scan(query, operation)
          SINK.scan(
            query: query,
            dialect: :postgresql,
            operation: operation
          )
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "pg", ">= 1.0"
          require "pg"

          ::PG::Connection.class_eval do
            extend Sinks::DSL

            [
              :send_query,
              :exec, # also known as: async_exec
              :async_exec,
              :sync_exec
            ].each do |method_name|
              presafe_sink_before method_name do |sql|
                Helpers.safe do
                  Helpers.scan(sql, method_name)
                end

                Aikido::Zen.idor_protect(sql, :postgresql)
              end
            end

            [
              :send_query_params,
              :exec_params, # also known as: async_exec_params
              :async_exec_params,
              :sync_exec_params
            ].each do |method_name|
              presafe_sink_before method_name do |sql, params|
                Helpers.safe do
                  Helpers.scan(sql, method_name)
                end

                Aikido::Zen.idor_protect(sql, :postgresql, params)
              end
            end

            def aikido_idor_prepared_statements
              @aikido_idor_prepared_statements ||= {}
            end

            [
              :send_prepare,
              :prepare, # also known as: async_prepare
              :async_prepare,
              :sync_prepare
            ].each do |method_name|
              presafe_sink_before method_name do |statement_name, sql|
                aikido_idor_prepared_statements[statement_name] = sql
              end
            end

            [
              :send_query_prepared,
              :exec_prepared, # also known as: async_exec_prepared
              :async_exec_prepared,
              :sync_exec_prepared
            ].each do |method_name|
              presafe_sink_before method_name do |statement_name, params|
                sql = aikido_idor_prepared_statements[statement_name]

                Helpers.safe do
                  Helpers.scan(sql, method_name)
                end

                Aikido::Zen.idor_protect(sql, :postgresql, params)
              end
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::PG.load_sinks!
