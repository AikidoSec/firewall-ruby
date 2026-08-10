require "test_helper"

# ActionController::Live runs the action in its own thread, where Zen's
# fiber-local context reads back as nil. rails/test_help stubs that thread away,
# so put it back to get the production behaviour under test.
ActionController::Live.class_eval do
  def new_controller_thread
    Thread.new { yield }.join
  end
end

class StreamsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed
  end

  test "streams successfully" do
    get "/streams", params: {token: "abc123"}

    assert_response :success
    assert_equal "data: ok\n\n", response.body
  end

  # Regression test for https://github.com/AikidoSec/firewall-ruby/issues/357.
  test "detects SQL injection in param from within the Live thread" do
    get "/streams", params: {token: "' OR 1=1--"}

    assert_response :internal_server_error
  end
end
