# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Request::SchemaTest < ActiveSupport::TestCase
  def build_schema(**args)
    Aikido::Zen::Request::Schema.new(**args)
  end

  def build_definition(data: {type: "string"})
    Aikido::Zen::Request::Schema::Definition.new(data)
  end

  def api_key_def(location: "location", name: "name")
    Aikido::Zen::Request::Schema::AuthSchemas::ApiKey.new(location, name)
  end

  def http_def(scheme: "scheme")
    Aikido::Zen::Request::Schema::AuthSchemas::Authorization.new(scheme)
  end

  def auth_schemas(schemas)
    Aikido::Zen::Request::Schema::AuthSchemas.new(schemas)
  end

  test "empty json decode into an empty schema" do
    assert_equal_schemas build_schema(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: EMPTY_SCHEMA,
      auth_schema: Aikido::Zen::Request::Schema::AuthSchemas.new([])
    ), from_json({})
  end

  test "correctly transformed" do
    assert_is_transformed build_schema(
      content_type: nil,
      body_schema: nil,
      query_schema: build_definition,
      auth_schema: auth_schemas([api_key_def, http_def])
    )

    assert_is_transformed build_schema(
      content_type: "json",
      body_schema: build_definition(data: {type: "number"}),
      query_schema: build_definition,
      auth_schema: auth_schemas([api_key_def, http_def])
    )

    assert_is_transformed build_schema(
      content_type: "json",
      body_schema: build_definition(data: {type: "number"}),
      query_schema: nil,
      auth_schema: auth_schemas([api_key_def, http_def])
    )

    assert_is_transformed build_schema(
      content_type: "json",
      body_schema: build_definition(data: {type: "number"}),
      query_schema: build_definition,
      auth_schema: nil
    )

    assert_is_transformed build_schema(
      content_type: "json",
      body_schema: build_definition(data: {type: "number"}),
      query_schema: build_definition,
      auth_schema: auth_schemas([api_key_def])
    )
  end

  def assert_is_transformed(schema)
    assert_equal_schemas schema, from_json(schema.as_json)
  end

  def assert_equal_schemas(schema_1, schema_2)
    assert_equal schema_1.as_json, schema_2.as_json
  end

  def from_json(hash)
    Aikido::Zen::Request::Schema.from_json(hash)
  end

  EMPTY_SCHEMA = Aikido::Zen::Request::Schema::EMPTY_SCHEMA
end
