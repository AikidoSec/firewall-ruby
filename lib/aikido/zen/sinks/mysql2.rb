# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module Mysql2
      SINK = Sinks.add("mysql2", scanners: [Scanners::SQLInjectionScanner])

      module Helpers
        def self.scan(query, operation)
          SINK.scan(query: query, dialect: :mysql, operation: operation)
        end
      end

      def self.load_sinks!
        if Aikido::Zen.satisfy "mysql2"
          require "mysql2"

          ::Mysql2::Client.class_eval do
            extend Sinks::DSL

            presafe_sink_before :query do |sql|
              Sinks::DSL.safe do
                Helpers.scan(sql, "query")
              end

              Aikido::Zen.idor_protect(sql, :mysql)
            end

            presafe_sink_after :prepare do |result, sql|
              result.aikido_idor_sql = sql
            end
          end

          ::Mysql2::Statement.class_eval do
            extend Sinks::DSL

            attr_accessor :aikido_idor_sql

            presafe_sink_before :execute do |*args, **kwargs|
              sql = aikido_idor_sql

              Sinks::DSL.safe do
                Helpers.scan(sql, "query")
              end

              Aikido::Zen.idor_protect(sql, :mysql, args)
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Mysql2.load_sinks!
