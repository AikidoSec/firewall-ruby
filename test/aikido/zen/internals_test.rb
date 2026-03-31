# frozen_string_literal: true

require "test_helper"

class Aikido::InternalsTest < ActiveSupport::TestCase
  Internals = Aikido::Zen::Internals

  test "it has a libzen version number" do
    refute_nil Aikido::Zen::LIBZEN_VERSION
  end

  test ".detect_sql_injection_native is attached" do
    assert Internals.singleton_methods.include?(:detect_sql_injection_native)
  end

  test ".detect_sql_injection is defined" do
    assert Internals.methods.include?(:detect_sql_injection)
  end

  test ".detect_sql_injection can detect SQL injection" do
    assert Internals.detect_sql_injection(
      "SELECT * FROM users WHERE id = '' OR 1=1 -- '",
      "' OR 1=1 -- ",
      Aikido::Zen::SQL::Dialects.fetch(:mysql)
    )
  end

  test ".idor_analyze_sql_native is attached" do
    assert Internals.singleton_methods.include?(:idor_analyze_sql_native)
  end

  test ".idor_free_string_native is attached" do
    assert Internals.singleton_methods.include?(:idor_free_string_native)
  end

  test ".idor_analyze_sql is defined" do
    assert Internals.methods.include?(:idor_analyze_sql)
  end

  test ".idor_analyze_sql can analyze SELECT queries" do
    result = Internals.idor_analyze_sql("SELECT * FROM users u WHERE u.tenant_id = $1", 9)
    assert_equal(
      [
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
      ],
      result
    )
  end

  test ".idor_analyze_sql can analyze INSERT queries" do
    result = Internals.idor_analyze_sql("INSERT INTO users (name, tenant_id) VALUES ('John', $1)", 9)
    assert_equal(
      [
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
      ],
      result
    )
  end

  test ".idor_analyze_sql returns a parse error value when the query cannot be parsed" do
    result = Internals.idor_analyze_sql("THIS IS NOT SQL", Aikido::Zen::SQL::Dialects.fetch(:mysql))

    assert_equal(
      {"error" => "sql parser error: Expected: an SQL statement, found: THIS at Line: 1, Column: 1"},
      result
    )
  end
end
