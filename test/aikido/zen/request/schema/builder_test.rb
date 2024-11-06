# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Request::Schema::BuilderTest < ActiveSupport::TestCase
  def builder_for_request(*args, **opts)
    env = Rack::MockRequest.env_for(*args, {input: nil}.merge(opts))
    context = Aikido::Zen::Context.from_rack_env(env)
    Aikido::Zen::Request::Schema::Builder.new(context: context)
  end

  def schema(definition)
    Aikido::Zen::Request::Schema::Definition.new(definition)
  end

  setup do
    Aikido::Zen.config.request_builder = Aikido::Zen::Context::RAILS_REQUEST_BUILDER
  end

  class GenericBehaviorTest < self
    def assert_type(builder, expected)
      if expected.nil?
        assert_nil builder.schema.content_type
      else
        assert_equal expected, builder.schema.content_type
      end
    end

    test "captures the request content type for JSON requests" do
      [
        "application/json",
        "application/x-json",
        "application/vnd.something+json",
        "application/vnd.something+json;v=2",
        "application/csp-report"
      ].each do |content_type|
        builder = builder_for_request("/", "CONTENT_TYPE" => content_type)
        assert_type builder, :json
      end
    end

    test "captures the request content type for XML requests" do
      [
        "application/xml",
        "text/xml"
      ].each do |content_type|
        builder = builder_for_request("/", "CONTENT_TYPE" => content_type)
        assert_type builder, :xml
      end
    end

    test "captures the request content type for urlencoded requests" do
      builder = builder_for_request("/", "CONTENT_TYPE" => "application/x-www-form-urlencoded")
      assert_type builder, :"form-urlencoded"
    end

    test "captures the request content type for form-data requests" do
      builder = builder_for_request("/", "CONTENT_TYPE" => "multipart/form-data")
      assert_type builder, :"form-data"
    end

    test "ignores unknown content types" do
      builder = builder_for_request("/", "CONTENT_TYPE" => "application/x-proprietary")
      assert_type builder, nil
    end
  end

  class AuthSchemaTest < self
    def builder_for_request(env, rails: true)
      env = Rack::MockRequest.env_for("/", env)

      context = if rails
        env = Rails.application.env_config.merge(env)
        Aikido::Zen::Context::RAILS_REQUEST_BUILDER.call(env)
      else
        Aikido::Zen::Context::RACK_REQUEST_BUILDER.call(env)
      end

      Aikido::Zen::Request::Schema::Builder.new(context: context)
    end

    def assert_includes_auth(builder, auth)
      assert_includes builder.schema.auth_schema.as_json, auth
    end

    test "detects Authorization header with bearer token" do
      builder = builder_for_request({"HTTP_AUTHORIZATION" => "Bearer 12345"})

      assert_includes_auth builder, {type: "http", scheme: "bearer"}
    end

    test "detects Basic Authentication" do
      builder = builder_for_request({"HTTP_AUTHORIZATION" => "Basic hexdigest"})

      assert_includes_auth builder, {type: "http", scheme: "basic"}
    end

    test "detects API keys in the Authorization header" do
      builder = builder_for_request({"HTTP_AUTHORIZATION" => "SomeKey"})

      assert_includes_auth builder, {type: "apiKey", in: :header, name: "Authorization"}
    end

    test "detects common API key headers" do
      {
        "HTTP_APIKEY" => "Apikey",
        "HTTP_API_KEY" => "Api-Key",
        "HTTP_TOKEN" => "Token",
        "HTTP_X_API_KEY" => "X-Api-Key",
        "HTTP_X_TOKEN" => "X-Token"
      }.each do |header, name|
        builder = builder_for_request({header => "SomeKey"})
        assert_includes_auth builder, {type: "apiKey", in: :header, name: name}
      end
    end

    test "detects common cookie names" do
      %w[user_id auth_token refresh_token].each do |name|
        builder = builder_for_request({"HTTP_COOKIE" => "#{name}=SomeKey"})
        assert_includes_auth builder, {type: "apiKey", in: :cookie, name: name}
      end
    end
  end

  class BodySchemaTest < self
    def builder_for_request(serialized_body, type: :json)
      content_type = Aikido::Zen::Request::Schema::Builder::DATA_TYPES.invert.fetch(type)
      super("/", "CONTENT_TYPE" => content_type, :input => serialized_body)
    end

    def assert_schema(builder, expected)
      assert_equal expected, builder.schema.body_schema
    end

    test "builds an empty schema when there's no body" do
      builder = builder_for_request("", type: :json)

      assert_schema builder, Aikido::Zen::Request::Schema::EMPTY_SCHEMA
    end

    test "extracts primitive properties from the body" do
      builder = builder_for_request(<<~JSON, type: :json)
        {"bool":true,"num":1.23,"int":100,"str":"hello","nil":null}
      JSON

      assert_schema builder, schema(
        type: "object",
        properties: {
          "bool" => schema(type: "boolean"),
          "num" => schema(type: "number"),
          "int" => schema(type: "integer"),
          "str" => schema(type: "string"),
          "nil" => schema(type: "null")
        }
      )
    end

    test "extracts arrays from the body" do
      builder = builder_for_request(<<~JSON, type: :json)
        [1, 2, 3, 4]
      JSON

      assert_schema builder, schema(
        type: "array",
        items: schema(type: "integer")
      )
    end

    test "only considers the first item on an array to determine subtype" do
      builder = builder_for_request(<<~JSON, type: :json)
        [1, "foo", "bar", "baz"]
      JSON

      assert_schema builder, schema(
        type: "array",
        items: schema(type: "integer")
      )
    end

    test "empty arrays don't include subtype information" do
      builder = builder_for_request(<<~JSON, type: :json)
        []
      JSON

      assert_schema builder, schema(type: "array")
    end

    test "handles objects nested in arrays" do
      builder = builder_for_request(<<~JSON, type: :json)
        [{"id":1}, {"id":2}, {"id":3}]
      JSON

      assert_schema builder, schema(
        type: "array",
        items: schema(
          type: "object",
          properties: {
            id: schema(type: "integer")
          }
        )
      )
    end

    test "handles arrays nested in objects" do
      builder = builder_for_request(<<~JSON, type: :json)
        {"users":[{"id": 1},{"id": 2}]}
      JSON

      assert_schema builder, schema(
        type: "object",
        properties: {
          "users" => schema(
            type: "array",
            items: schema(
              type: "object",
              properties: schema(
                id: schema(type: "integer")
              )
            )
          )
        }
      )
    end

    test "only inspects the first @config.api_schema_collection_max_properties props in a hash" do
      Aikido::Zen.config.api_schema_collection_max_properties = 3

      builder = builder_for_request(<<~JSON, type: :json)
        {"one":1,"two":2,"three":3,"four":4}
      JSON

      assert_schema builder, schema(
        type: "object",
        properties: {
          one: schema(type: "integer"),
          two: schema(type: "integer"),
          three: schema(type: "integer")
        }
      )
    end

    test "only recurs @config.api_schema_collection_max_depth levels into a deep structure" do
      Aikido::Zen.config.api_schema_collection_max_depth = 3

      builder = builder_for_request(<<~JSON, type: :json)
        {"one": {"two": {"three": {"four": "that's deep"}}}}
      JSON

      assert_schema builder, schema(
        type: "object",
        properties: {
          one: schema(
            type: "object",
            properties: {
              two: schema(
                type: "object",
                properties: {
                  three: schema(type: "object", properties: {})
                }
              )
            }
          )
        }
      )
    end

    test "extracts the schema from multipart/form-data requests" do
      builder = builder_for_request(<<~BODY, type: :"form-data")
        post[title]="Title"&post[tags][]=foo&post[tags][]=bar
      BODY

      assert_schema builder, schema(
        type: "object",
        properties: {
          "post" => schema(
            type: "object",
            properties: {
              "title" => schema(type: "string"),
              "tags" => schema(
                type: "array",
                items: schema(type: "string")
              )
            }
          )
        }
      )
    end

    test "all primitive values are treated as strings in multipart/form-data" do
      builder = builder_for_request(<<~BODY, type: :"form-data")
        foo=1&bar=1.2&baz=false
      BODY

      assert_schema builder, schema(
        type: "object",
        properties: {
          "foo" => schema(type: "string"),
          "bar" => schema(type: "string"),
          "baz" => schema(type: "string")
        }
      )
    end
  end

  class QuerySchemaTest < self
    def builder_for_request(query_string)
      super("/?#{query_string}".chomp("?"))
    end

    def assert_schema(builder, expected)
      assert_equal expected, builder.schema.query_schema
    end

    test "extracts values from the query string" do
      builder = builder_for_request(<<~QUERY)
        one=foo&two=bar
      QUERY

      assert_schema builder, schema(
        type: "object",
        properties: {
          "one" => schema(type: "string"),
          "two" => schema(type: "string")
        }
      )
    end

    test "all primitives are treated as strings in the query string" do
      builder = builder_for_request(<<~QUERY)
        foo=1&bar=1.2&baz=false
      QUERY

      assert_schema builder, schema(
        type: "object",
        properties: {
          "foo" => schema(type: "string"),
          "bar" => schema(type: "string"),
          "baz" => schema(type: "string")
        }
      )
    end

    test "extracts objects from the query string" do
      builder = builder_for_request(<<~QUERY)
        user[email]=jane@example.com&user[name]=Jane+Doe
      QUERY

      assert_schema builder, schema(
        type: "object",
        properties: {
          "user" => schema(
            type: "object",
            properties: {
              "name" => schema(type: "string"),
              "email" => schema(type: "string")
            }
          )
        }
      )
    end

    test "extracts arrays from the query string" do
      builder = builder_for_request(<<~QUERY)
        tags[]=foo&tags[]=bar
      QUERY

      assert_schema builder, schema(
        type: "object",
        properties: {
          "tags" => schema(
            type: "array",
            items: schema(type: "string")
          )
        }
      )
    end
  end
end
