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

  test "detects SQL injection in cookie with poison header name triggering header normalization error" do
    cookies[:token] = "caf%C3%A9' OR 1=1--"

    get "/api/v1/profile", headers: {"X--Attack" => "1"}

    assert_response :internal_server_error

    assert_blocked_sql_injection
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
