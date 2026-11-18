require "test_helper"

# ActionController::Live runs the action in its own thread, where Zen's
# fiber-local current context reads back as nil unless it is inherited.
# The test case stubs that thread away, so put Rails' own method back
# to get the original behavior.
rails_new_controller_thread = ActionController::Live.instance_method(:new_controller_thread)

require "action_controller/test_case"

ActionController::Live.send(:define_method, :new_controller_thread, rails_new_controller_thread)

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
