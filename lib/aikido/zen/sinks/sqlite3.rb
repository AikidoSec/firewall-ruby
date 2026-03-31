# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module SQLite3
      SINK = Sinks.add("sqlite3", scanners: [Scanners::SQLInjectionScanner])

      module Helpers
        def self.scan(query, operation)
          SINK.scan(
            query: query,
            dialect: :sqlite,
            operation: operation
          )
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "sqlite3", ">= 1.0"
          require "sqlite3"

          ::SQLite3::Database.class_eval do
            extend Sinks::DSL

            [
              :execute,
              :execute_batch
            ].each do |method_name|
              presafe_sink_before method_name do |sql, bind_vars|
                Sinks::DSL.safe do
                  Helpers.scan(sql, "database.execute")
                end

                Aikido::Zen.idor_protect(sql, :sqlite)
              end
            end

            # SQLite3::Database#exec_batch is an internal native private method.
            presafe_sink_before :exec_batch do |sql, *args, **kwargs|
              Sinks::DSL.safe do
                Helpers.scan(sql, "exec_batch")
              end

              Aikido::Zen.idor_protect(sql, :sqlite)
            end

            alias_method :prepare__internal_for_aikido_zen, :prepare

            def prepare(*args, **kwargs, &blk)
              sql, = args

              Sinks::DSL.safe do
                Helpers.scan(sql, "statement.execute")
              end

              unless blk
                result = prepare__internal_for_aikido_zen(*args, **kwargs)
                result.aikido_idor_sql = sql
                return result
              end

              prepare__internal_for_aikido_zen(*args, **kwargs) do |stmt|
                stmt.aikido_idor_sql = sql
                blk.call(stmt)
              end
            end
          end

          ::SQLite3::Statement.class_eval do
            extend Sinks::DSL

            attr_accessor :aikido_idor_sql

            presafe_sink_before :execute do |*bind_vars|
              sql = aikido_idor_sql

              Sinks::DSL.safe do
                Helpers.scan(sql, "statement.execute")
              end

              Aikido::Zen.idor_protect(sql, :sqlite, bind_vars)
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::SQLite3.load_sinks!
