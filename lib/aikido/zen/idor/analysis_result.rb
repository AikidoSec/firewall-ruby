# frozen_string_literal: true

module Aikido::Zen
  module IDOR
    class Table
      def self.from_json(data)
        new(
          name: data["name"],
          alt_name: data["alias"]
        )
      end

      # @param name [String]
      # @param alt_name [String, nil]
      def initialize(name:, alt_name: nil)
        @name = name
        @alt_name = alt_name
      end

      # @return [String]
      attr_accessor :name
      # @return [String, nil]
      attr_accessor :alt_name

      def ==(other)
        other.is_a?(self.class) &&
          other.name == name &&
          other.alt_name == alt_name
      end
      alias_method :eql?, :==
    end

    class FilterColumn
      def self.from_json(data)
        new(
          table_qualifier: data["table"],
          name: data["column"],
          value: data["value"],
          is_placeholder: data["is_placeholder"],
          placeholder_number: data["placeholder_number"]
        )
      end

      # @param table_qualifier [String, nil]
      # @param name [String]
      # @param value [String]
      # @param is_placeholder [Boolean]
      # @param placeholder_number [Integer, nil]
      def initialize(table_qualifier:, name:, value:, is_placeholder:, placeholder_number: nil)
        @table_qualifier = table_qualifier
        @name = name
        @value = value
        @is_placeholder = is_placeholder
        @placeholder_number = placeholder_number
      end

      # @return [String, nil]
      attr_accessor :table_qualifier

      # @return [String]
      attr_accessor :name

      # @return [String]
      attr_accessor :value

      # @return [Boolean]
      attr_accessor :is_placeholder

      # @return [Integer, nil]
      attr_accessor :placeholder_number

      def ==(other)
        other.is_a?(self.class) &&
          other.table_qualifier == table_qualifier &&
          other.name == name &&
          other.value == value &&
          other.is_placeholder == is_placeholder &&
          other.placeholder_number == placeholder_number
      end
      alias_method :eql?, :==
    end

    class InsertColumn
      def self.from_json(data)
        new(
          name: data["column"],
          value: data["value"],
          is_placeholder: data["is_placeholder"],
          placeholder_number: data["placeholder_number"]
        )
      end

      # @param name [String]
      # @param value [String]
      # @param is_placeholder [Boolean]
      # @param placeholder_number [Integer, nil]
      def initialize(name:, value:, is_placeholder:, placeholder_number: nil)
        @name = name
        @value = value
        @is_placeholder = is_placeholder
        @placeholder_number = placeholder_number
      end

      # @return [String]
      attr_accessor :name

      # @return [String]
      attr_accessor :value

      # @return [Boolean]
      attr_accessor :is_placeholder

      # @return [Integer, nil]
      attr_accessor :placeholder_number

      def ==(other)
        other.is_a?(self.class) &&
          other.name == name &&
          other.value == value &&
          other.is_placeholder == is_placeholder &&
          other.placeholder_number == placeholder_number
      end
      alias_method :eql?, :==
    end

    class SQLQueryResult
      def self.from_json(data)
        new(
          kind: data["kind"].to_sym,
          tables: data["tables"].map { |value| Table.from_json(value) },
          filter_columns: data["filters"].map { |value| FilterColumn.from_json(value) },
          insert_columns: data["insert_columns"]&.map do |values|
            values.map { |value| InsertColumn.from_json(value) }
          end
        )
      end

      # @param kind [:select, :insert, :update, :delete]
      # @param tables [Array<Aikido::Zen::IDOR::Table>]
      # @param filter_columns [Array<Aikido::Zen::IDOR::FilterColumn>]
      # @param insert_columns [Array<Array<Aikido::Zen::IDOR::InsertColumn>>, nil]
      def initialize(kind:, tables:, filter_columns:, insert_columns: nil)
        raise ArgumentError, "kind must be one of :select, :insert, :update, or :delete" unless [:select, :insert, :update, :delete].include?(kind)

        @kind = kind
        @tables = tables
        @filter_columns = filter_columns
        @insert_columns = insert_columns
      end

      # @return [:select, :insert, :update, :delete]
      attr_accessor :kind

      # @return [Array<Aikido::Zen::IDOR::Table>]
      attr_accessor :tables

      # @return [Array<Aikido::Zen::IDOR::FilterColumn>]
      attr_accessor :filter_columns

      # @return [Array<Array<Aikido::Zen::IDOR::InsertColumn>>, nil]
      attr_accessor :insert_columns

      def ==(other)
        other.is_a?(self.class) &&
          other.kind == kind &&
          other.tables == tables &&
          other.filter_columns == filter_columns &&
          other.insert_columns == insert_columns
      end
      alias_method :eql?, :==
    end
  end
end
