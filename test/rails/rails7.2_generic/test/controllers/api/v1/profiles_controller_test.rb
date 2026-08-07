require "test_helper"
require "json"

# ActionController::TestCase dispatches straight to the controller, so the Zen
# middleware never runs and there is no context for the callbacks to pick up.
# Regression test for https://github.com/AikidoSec/firewall-ruby/issues/357.
class Api::V1::ProfilesControllerTest < ActionController::TestCase
  tests Api::V1::ProfilesController

  setup do
    Rails.application.load_seed
  end

  test "request is unauthorized without token cookie" do
    get :show

    assert_response :unauthorized
    assert_equal({"error" => "No token cookie"}, JSON.parse(response.body))
  end

  test "request is authorized with token cookie" do
    cookies[:token] = "abc123"

    get :show

    assert_response :success
    assert_equal [["Alice", "public_info"]], JSON.parse(response.body)
  end
end
