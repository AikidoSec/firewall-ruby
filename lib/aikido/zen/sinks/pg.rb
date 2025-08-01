# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module PG
      def self.load_sinks!
        if Aikido::Zen.satisfy "pg", ">= 1.0"
          require "pg"

          ::PG::Connection.prepend(PG::ConnectionExtensions)
        end
      end

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

      module ConnectionExtensions
        extend Sinks::DSL

        %i[
          send_query exec sync_exec async_exec
          send_query_params exec_params sync_exec_params async_exec_params
        ].each do |method_name|
          presafe_sink_before method_name do |query|
            Helpers.safe do
              Helpers.scan(query, method_name)
            end
          end
        end

        %i[
          send_prepare prepare async_prepare sync_prepare
        ].each do |method_name|
          presafe_sink_before method_name do |_, query|
            Helpers.safe do
              Helpers.scan(query, method_name)
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::PG.load_sinks!
