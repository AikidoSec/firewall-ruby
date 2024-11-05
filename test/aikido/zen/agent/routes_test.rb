# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Agent::RoutesTest < ActiveSupport::TestCase
  setup { @routes = Aikido::Zen::Agent::Routes.new }

  test "adding routes without a schema" do
    get_root = build_route("GET", "/")
    post_users = build_route("POST", "/users")

    @routes.add(get_root.dup)
    @routes.add(get_root.dup)
    @routes.add(post_users.dup)

    refute_empty @routes

    assert_equal 2, @routes[get_root].hits
    assert_equal 1, @routes[post_users].hits
  end

  test "adding routes with a schema" do
    get_root = build_route("GET", "/")
    post_users = build_route("POST", "/users")

    @routes.add(get_root.dup, Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: EMPTY_SCHEMA,
      auth_schema: NO_AUTH
    ))
    @routes.add(get_root.dup, Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: build_schema(
        type: "object",
        properties: {mode: build_schema(type: "string")}
      ),
      auth_schema: auth_schema(build_auth(:cookie, "user_id"))
    ))
    @routes.add(post_users.dup, Aikido::Zen::Request::Schema.new(
      content_type: :json,
      body_schema: build_schema(
        type: "object",
        properties: {name: build_schema(type: "string")}
      ),
      query_schema: EMPTY_SCHEMA,
      auth_schema: auth_schema(build_auth(:cookie, "user_id"))
    ))

    assert_equal 2, @routes[get_root].hits
    assert_equal @routes[get_root].schema.as_json, {
      # body gets removed because neither request had a body
      query: {
        "type" => "object",
        "properties" => {"mode" => {"type" => "string"}}
      },
      auth: [
        {type: "apiKey", in: :cookie, name: "user_id"}
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
        {type: "apiKey", in: :cookie, name: "user_id"}
      ]
    }
  end

  test "#as_json serializes as a list of routes including the schema" do
    get_root = build_route("GET", "/")
    post_users = build_route("POST", "/users")

    @routes.add(get_root.dup, Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: EMPTY_SCHEMA,
      auth_schema: NO_AUTH
    ))
    @routes.add(get_root.dup, Aikido::Zen::Request::Schema.new(
      content_type: nil,
      body_schema: EMPTY_SCHEMA,
      query_schema: build_schema(
        type: "object",
        properties: {mode: build_schema(type: "string")}
      ),
      auth_schema: NO_AUTH
    ))
    @routes.add(post_users.dup, Aikido::Zen::Request::Schema.new(
      content_type: :json,
      body_schema: build_schema(
        type: "object",
        properties: {name: build_schema(type: "string")}
      ),
      query_schema: EMPTY_SCHEMA,
      auth_schema: NO_AUTH
    ))

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

  test "#as_json omits apispec if the schema is not given for the route" do
    @routes.add(build_route("GET", "/"))

    assert_equal [{method: "GET", path: "/", hits: 1}], @routes.as_json
  end

  def build_route(verb, path)
    Aikido::Zen::Route.new(verb: verb, path: path)
  end

  def build_schema(definition)
    Aikido::Zen::Request::Schema::Definition.new(definition)
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
