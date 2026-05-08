# frozen_string_literal: true

require "test_helper"

class Aikido::IDORTest < ActiveSupport::TestCase
  Table = Aikido::Zen::IDOR::Table
  FilterColumn = Aikido::Zen::IDOR::FilterColumn
  InsertColumn = Aikido::Zen::IDOR::InsertColumn
  SQLQueryResult = Aikido::Zen::IDOR::SQLQueryResult

  class SQLQueryResultTest < ActiveSupport::TestCase
    test ".from_json deserializes SELECT queries" do
      data = [
        {
          "kind" => "select",
          "tables" => [
            {
              "name" => "users",
              "alias" => "u"
            }
          ],
          "filters" => [
            {
              "table" => "u",
              "column" => "tenant_id",
              "value" => "$1",
              "is_placeholder" => true
            }
          ]
        }
      ]

      expected = [
        SQLQueryResult.new(
          kind: :select,
          tables: [
            Table.new(
              name: "users",
              alt_name: "u"
            )
          ],
          filter_columns: [
            FilterColumn.new(
              table_qualifier: "u",
              name: "tenant_id",
              value: "$1",
              is_placeholder: true
            )
          ]
        )
      ]

      actual = data.map do |value|
        SQLQueryResult.from_json(value)
      end

      assert_equal expected, actual
    end

    test ".from_json deserializes INSERT queries" do
      data = [
        {
          "kind" => "insert",
          "tables" => [
            {
              "name" => "users"
            }
          ],
          "filters" => [],
          "insert_columns" => [
            [
              {
                "column" => "name",
                "value" => "John",
                "is_placeholder" => false
              },
              {
                "column" => "tenant_id",
                "value" => "$1",
                "is_placeholder" => true
              }
            ]
          ]
        }
      ]

      expected = [
        SQLQueryResult.new(
          kind: :insert,
          tables: [
            Table.new(
              name: "users"
            )
          ],
          filter_columns: [],
          insert_columns: [
            [
              InsertColumn.new(
                name: "name",
                value: "John",
                is_placeholder: false
              ),
              InsertColumn.new(
                name: "tenant_id",
                value: "$1",
                is_placeholder: true
              )
            ]
          ]
        )
      ]

      actual = data.map do |value|
        SQLQueryResult.from_json(value)
      end

      assert_equal expected, actual
    end

    test "#initialize raises ArgumentError if kind is not one of :select, :insert, :update, or :delete" do
      [:select, :insert, :update, :delete].each do |kind|
        assert_silent do
          SQLQueryResult.new(
            kind: kind,
            tables: [],
            filter_columns: [],
            insert_columns: []
          )
        end
      end

      ["select", :INSERT, "UPDATE", :other, 123].each do |kind|
        err = assert_raises(ArgumentError) do
          SQLQueryResult.new(
            kind: kind,
            tables: [],
            filter_columns: [],
            insert_columns: []
          )
        end

        assert_equal "kind must be one of :select, :insert, :update, or :delete", err.message
      end
    end
  end
end
