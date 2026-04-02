# frozen_string_literal: true

module Aikido::Zen
  module IDOR
    class Error < StandardError
    end

    class Protector
      # @api private
      # Visible for testing.
      attr_accessor :cache

      def initialize(config: Aikido::Zen.config)
        @config = config

        @cache = CappedMap.new(@config.idor_max_cache_entries, mode: :lru)
      end

      # @param sql [String]
      # @param dialect_name [Symbol]
      # @param context [Aikido::Zen::Context]
      # @raise [Aikido::Zen::IDOR::Error]
      def protect(sql, dialect_name, params, context)
        return unless @config.idor_protection_enabled? && context.idor_protection_enabled?

        tenant_id = context.request.tenant_id

        if tenant_id.nil?
          raise Aikido::Zen::IDOR::Error.new("Zen IDOR protection: Aikido::Zen.set_tenant_id was not called for this request. Every request must have a tenant ID when IDOR protection is enabled.")
        end

        dialect = Aikido::Zen::SQL::Dialects.fetch(dialect_name)

        analysis = analyze(sql, dialect)

        analysis.each do |query_result|
          if query_result.kind == :insert
            protect_insert(dialect, query_result, tenant_id, params)
          else
            protect_filter(dialect, query_result, tenant_id, params)
          end
        end
      end

      private

      # @param sql [String]
      # @param dialect [Aikido::Zen::SQL::Dialects::Dialect]
      # @return [Array<Aikido::Zen::IDOR::SQLQueryResult>]
      # @raise [Aikido::Zen::IDOR::Error]
      def analyze(sql, dialect)
        cache_key = [dialect.internals_key, sql]

        analysis = @cache[cache_key]
        return analysis if analysis

        analysis = Internals.idor_analyze_sql(sql, dialect)

        # :nocov:
        unless analysis
          raise IDOR::Error, "Zen IDOR protection: failed to analyze SQL query"
        end
        # :nocov:

        if analysis.is_a?(Hash) && analysis["error"]
          raise IDOR::Error, "Zen IDOR protection: #{analysis["error"]}"
        end

        result = analysis.map do |value|
          Aikido::Zen::IDOR::SQLQueryResult.from_json(value)
        end

        @cache[cache_key] = result

        result
      end

      def protect_insert(dialect, query_result, tenant_id, params)
        query_result.tables.each do |table|
          next if @config.idor_excluded_table_names.include?(table.name)

          unless query_result.insert_columns
            # INSERT ... SELECT without explicit columns — can't verify tenant column
            raise IDOR::Error, "Zen IDOR protection: INSERT on table '#{table.name}' is missing column '#{@config.idor_tenant_column_name}'"
          end

          query_result.insert_columns.each do |row|
            tenant_column = row.find { |column| column.name == @config.idor_tenant_column_name }

            unless tenant_column
              raise IDOR::Error, "Zen IDOR protection: INSERT on table '#{table.name}' is missing column '#{@config.idor_tenant_column_name}'"
            end

            resolved_tenant_id = tenant_column.value

            if tenant_column.is_placeholder
              resolved_tenant_id = dialect.resolve_placeholder(tenant_column.value, tenant_column.placeholder_number, params)

              unless resolved_tenant_id
                raise IDOR::Error, "Zen IDOR protection: INSERT on table '#{table.name}' has a placeholder for '#{@config.idor_tenant_column_name}' that could not be resolved"
              end
            end

            if resolved_tenant_id.to_s != tenant_id.to_s
              raise IDOR::Error, "Zen IDOR protection: INSERT on table '#{table.name}' sets '#{@config.idor_tenant_column_name}' to '#{resolved_tenant_id}' but tenant ID is '#{tenant_id}'"
            end
          end
        end
      end

      def protect_filter(dialect, query_result, tenant_id, params)
        query_result.tables.each do |table|
          next if @config.idor_excluded_table_names.include?(table.name)

          tenant_column = query_result.filter_columns.find do |column|
            next false if column.name != @config.idor_tenant_column_name

            next column.table_qualifier == table.name || column.table_qualifier == table.alt_name if column.table_qualifier

            # Unqualified column (e.g. WHERE tenant_id = $1 without table prefix):
            # We can only safely attribute it to the current table when there's
            # exactly one table in the query. With multiple tables, we can't know
            # which table the unqualified column belongs to.
            query_result.tables.size == 1
          end

          unless tenant_column
            raise IDOR::Error, "Zen IDOR protection: query on table '#{table.name}' is missing column '#{@config.idor_tenant_column_name}'"
          end

          resolved_tenant_id = tenant_column.value

          if tenant_column.is_placeholder
            resolved_tenant_id = dialect.resolve_placeholder(tenant_column.value, tenant_column.placeholder_number, params)

            unless resolved_tenant_id
              raise IDOR::Error, "Zen IDOR protection: query on table '#{table.name}' has a placeholder for '#{@config.idor_tenant_column_name}' that could not be resolved"
            end
          end

          if resolved_tenant_id.to_s != tenant_id.to_s
            raise IDOR::Error, "Zen IDOR protection: query on table '#{table.name}' sets '#{@config.idor_tenant_column_name}' to '#{resolved_tenant_id}' but tenant ID is '#{tenant_id}'"
          end
        end
      end
    end
  end
end
