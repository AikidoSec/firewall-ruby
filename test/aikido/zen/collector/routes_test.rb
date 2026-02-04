# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Collector::RoutesTest < ActiveSupport::TestCase
  setup {
    @config = Aikido::Zen.config
    @routes = Aikido::Zen::Collector::Routes.new(@config)
  }

  test "adding requests without a schema" do
    get_root = build_route("GET", "/")
    post_users = build_route("POST", "/users")

    get_request = build_request(get_root)
    post_request = build_request(post_users)

    request = get_request.dup
    @routes.add(request.route, request.schema)

    request = get_request.dup
    @routes.add(request.route, request.schema)

    request = post_request.dup
    @routes.add(request.route, request.schema)

    refute_empty @routes

    assert_equal 2, @routes[get_root].hits
    assert_equal 1, @routes[post_users].hits
  end

  test "adding requests with a schema" do
    empty_schema = Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: EMPTY_SCHEMA,
      auth_schema: NO_AUTH
    )
    query_schema = Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: build_schema(
        type: "object",
        properties: {mode: build_schema(type: "string")}
      ),
      auth_schema: auth_schema(build_auth(:cookie, "user_id"))
    )
    body_schema = Aikido::Zen::Request::Schema.new(
      content_type: :json,
      body_schema: build_schema(
        type: "object",
        properties: {name: build_schema(type: "string")}
      ),
      query_schema: EMPTY_SCHEMA,
      auth_schema: auth_schema(build_auth(:cookie, "user_id"))
    )

    get_root = build_route("GET", "/")
    post_users = build_route("POST", "/users")

    request = build_request(get_root.dup, empty_schema)
    @routes.add(request.route, request.schema)

    request = build_request(get_root.dup, query_schema)
    @routes.add(request.route, request.schema)

    request = build_request(post_users.dup, body_schema)
    @routes.add(request.route, request.schema)

    assert_equal 2, @routes[get_root].hits
    assert_equal @routes[get_root].schema.as_json, {
      # body gets removed because neither request had a body
      query: {
        "type" => "object",
        "properties" => {"mode" => {"type" => "string"}}
      },
      auth: [
        {"type" => "apiKey", "in" => :cookie, "name" => "user_id"}
      ]
    }

    assert_equal 1, @routes[post_users].hits
    assert_equal @routes[post_users].schema.as_json, {
      body: {
        type: :json,
        schema: {
          "type" => "object",
          "properties" => {"name" => {"type" => "string"}}
        }
      },
      auth: [
        {"type" => "apiKey", "in" => :cookie, "name" => "user_id"}
      ]
    }
  end

  test "#as_json serializes as a list of routes including the schema" do
    empty_schema = Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: EMPTY_SCHEMA,
      auth_schema: NO_AUTH
    )
    query_schema = Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: build_schema(
        type: "object",
        properties: {mode: build_schema(type: "string")}
      ),
      auth_schema: NO_AUTH
    )
    body_schema = Aikido::Zen::Request::Schema.new(
      content_type: :json,
      body_schema: build_schema(
        type: "object",
        properties: {name: build_schema(type: "string")}
      ),
      query_schema: EMPTY_SCHEMA,
      auth_schema: NO_AUTH
    )

    get_root = build_route("GET", "/")
    post_users = build_route("POST", "/users")

    request = build_request(get_root.dup, empty_schema)
    @routes.add(request.route, request.schema)

    request = build_request(get_root.dup, query_schema)
    @routes.add(request.route, request.schema)

    request = build_request(post_users.dup, body_schema)
    @routes.add(request.route, request.schema)

    assert_equal @routes.as_json, [
      {
        method: "GET",
        path: "/",
        hits: 2,
        apispec: {
          query: {
            "type" => "object",
            "properties" => {"mode" => {"type" => "string"}}
          }
        }
      },
      {
        method: "POST",
        path: "/users",
        hits: 1,
        apispec: {
          body: {
            type: :json,
            schema: {
              "type" => "object",
              "properties" => {"name" => {"type" => "string"}}
            }
          }
        }
      }
    ]
  end

  test "the schema is only collected {api_schema_max_samples} times" do
    root_route = build_route("GET", "/")

    sampled_request = build_request(root_route, Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: EMPTY_SCHEMA,
      auth_schema: NO_AUTH
    ))

    @config.api_schema_max_samples = 3

    assert_difference -> { @routes[root_route].samples }, +3 do
      3.times do
        @routes.add(sampled_request.route, sampled_request.schema)
      end
    end

    unsampled_request = build_request(root_route)

    assert_difference -> { @routes[root_route].samples }, +0 do
      @routes.add(unsampled_request.route, unsampled_request.schema)
    end
  end

  test "setting {api_schema_max_samples} to 0 disables sampling" do
    root_route = build_route("GET", "/")

    unsampled_request = build_request(root_route)

    @config.api_schema_max_samples = 0

    assert_difference -> { @routes.visits[root_route].samples }, +0 do
      @routes.add(unsampled_request.route, unsampled_request.schema)
    end

    assert_nil @routes[unsampled_request.route].schema.as_json
  end

  test "#as_json omits apispec if the schema is not given for the route" do
    request = build_request(build_route("GET", "/"))
    @routes.add(request.route, request.schema)

    assert_equal [{method: "GET", path: "/", hits: 1}], @routes.as_json
  end

  def build_route(verb, path)
    Aikido::Zen::Route.new(verb: verb, path: path)
  end

  def build_schema(definition)
    Aikido::Zen::Request::Schema::Definition.new(definition)
  end

  def build_request(route, schema = nil)
    OpenStruct.new(route: route, schema: schema)
  end

  def auth_schema(*atoms)
    Aikido::Zen::Request::Schema::AuthSchemas.new(atoms)
  end

  def build_auth(type, name)
    case type
    when :http
      Aikido::Zen::Request::Schema::AuthSchemas::Authorization.new(name)
    when :cookie, :header
      Aikido::Zen::Request::Schema::AuthSchemas::ApiKey.new(type, name)
    end
  end

  EMPTY_SCHEMA = Aikido::Zen::Request::Schema::EMPTY_SCHEMA
  NO_AUTH = Aikido::Zen::Request::Schema::AuthSchemas::NONE
end
