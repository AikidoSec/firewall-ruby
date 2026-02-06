# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Request::Schema::AuthSchemasTest < ActiveSupport::TestCase
  test "#as_json serializes each schema in the list" do
    schema = auth_schema(
      build_auth(:http, "basic"),
      build_auth(:header, "X-Api-Key"),
      build_auth(:cookie, "user_id")
    )

    expected = [
      {"type" => "http", "scheme" => "basic"},
      {"type" => "apiKey", "in" => :header, "name" => "X-Api-Key"},
      {"type" => "apiKey", "in" => :cookie, "name" => "user_id"}
    ]

    assert_equal expected, schema.as_json
  end

  test "#as_json serializes the empty list as nil" do
    assert_nil NONE.as_json
  end

  test "#merge two empty lists" do
    empty_1 = auth_schema
    empty_2 = auth_schema

    assert_equal NONE, empty_1 | empty_2
  end

  test "#merge concatenates" do
    schema_1 = auth_schema(build_auth(:http, "basic"))
    schema_2 = auth_schema(build_auth(:http, "bearer"))

    expected = auth_schema(
      build_auth(:http, "basic"),
      build_auth(:http, "bearer")
    )

    assert_equal expected, schema_1 | schema_2
  end

  test "#merge removes duplicates" do
    schema_1 = auth_schema(
      build_auth(:http, "bearer"),
      build_auth(:http, "basic"),
      build_auth(:cookie, "user_id")
    )
    schema_2 = auth_schema(
      build_auth(:http, "bearer"),
      build_auth(:cookie, "user_id")
    )

    expected = auth_schema(
      build_auth(:http, "bearer"),
      build_auth(:http, "basic"),
      build_auth(:cookie, "user_id")
    )

    assert_equal expected, schema_1 | schema_2
  end

  test ".from_json raises when the schema type is invalid" do
    schema_1 = auth_schema(
      Fruit.new("apple", "red"),
      Fruit.new("apple", "green"),
      Fruit.new(nil, "blue")
    )

    schema_1_data = schema_1.as_json

    assert_raises do
      auth_schema_from_json(schema_1_data)
    end

    schema_2 = auth_schema(
      build_auth(:http, "bearer"),
      Fruit.new(nil, "blue"),
      build_auth(:cookie, "user_id")
    )

    schema_2_data = schema_2.as_json

    assert_raises do
      auth_schema_from_json(schema_2_data)
    end
  end

  def auth_schema(*atoms)
    Aikido::Zen::Request::Schema::AuthSchemas.new(atoms)
  end

  def auth_schema_from_json(data)
    Aikido::Zen::Request::Schema::AuthSchemas.from_json(data)
  end

  def build_auth(type, name)
    case type
    when :http
      Aikido::Zen::Request::Schema::AuthSchemas::Authorization.new(name)
    when :cookie, :header
      Aikido::Zen::Request::Schema::AuthSchemas::ApiKey.new(type, name)
    end
  end

  NONE = Aikido::Zen::Request::Schema::AuthSchemas::NONE

  Fruit = Struct.new(:type, :color) do
    def as_json
      {"type" => type, "color" => color.downcase}
    end
  end
end
