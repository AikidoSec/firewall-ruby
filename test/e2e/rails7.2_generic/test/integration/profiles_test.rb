require "test_helper"
require "json"

class ProfilesTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed
  end

  test "request is unauthorized without token cookie" do
    get "/api/v1/profile"

    assert_response :unauthorized

    assert_response_body_json({
      "error" => "No token cookie"
    })
  end

  test "request is authorized with token cookie" do
    cookies[:token] = "abc123"

    get "/api/v1/profile"

    assert_response :success

    assert_response_body_json([
      ["Alice", "public_info"]
    ])
  end

  test "detects SQL injection in cookie" do
    cookies[:token] = "caf%C3%A9' OR 1=1--"

    get "/api/v1/profile"

    assert_response :internal_server_error

    assert_blocked_sql_injection
  end

  test "detects SQL injection in cookie with poison header value triggering encoding compatibility error" do
    cookies[:token] = "caf%C3%A9' OR 1=1--"

    get "/api/v1/profile", headers: {"X-Poison" => "\xFF\xFF"}

    assert_response :internal_server_error

    assert_blocked_sql_injection
  end

  test "detects SQL injection in body with JSON content type" do
    cookies[:token] = "supersecret"

    params = {
      user: {
        secret: "NEW_SECRET', name='NEW_NAME"
      }
    }.to_json

    patch "/api/v1/profile",
      params: params,
      headers: {
        "Content-Type" => "application/json"
      }

    assert_response :internal_server_error

    assert_blocked_sql_injection
  end

  test "detects SQL injection in body with XML content type" do
    cookies[:token] = "supersecret"

    params = {
      user: {
        secret: "NEW_SECRET', name='NEW_NAME"
      }
    }.to_xml_root

    patch "/api/v1/profile",
      params: params,
      headers: {
        "Content-Type" => "application/xml"
      }

    assert_response :internal_server_error

    assert_blocked_sql_injection
  end

  test "detects SQL injection in body and unhandled content type" do
    cookies[:token] = "supersecret"

    params = {
      user: {
        secret: "NEW_SECRET', name='NEW_NAME"
      }
    }.to_yaml

    patch "/api/v1/profile",
      params: params,
      headers: {
        "Content-Type" => "application/yaml"
      }

    assert_response :success
  end

  test "detects SQL injection in body with incorrect content type" do
    cookies[:token] = "supersecret"

    params = {
      user: {
        secret: "NEW_SECRET', name='NEW_NAME"
      }
    }.to_json

    patch "/api/v1/profile",
      params: params,
      headers: {
        "Content-Type" => "application/xml"
      }

    assert_response :internal_server_error

    json_body = JSON.parse(response.body)

    assert_equal "ActionDispatch::Http::Parameters::ParseError", json_body["error"]
  end

  private

  def assert_response_body_json(expected)
    assert_equal expected, JSON.parse(response.body)
  end

  def assert_blocked_sql_injection
    assert_response_body_json({
      "error" => "ActiveRecord::StatementInvalid",
      "message" => "Aikido::Zen::SQLInjectionError: Aikido::Zen::SQLInjectionError",
      "cause" => "Aikido::Zen::SQLInjectionError"
    })
  end
end
