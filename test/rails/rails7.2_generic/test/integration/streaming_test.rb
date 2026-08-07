require "test_helper"

# ActionController::Live runs the action in its own thread, where Zen's
# fiber-local context reads back as nil. rails/test_help stubs that thread away,
# so put it back to get the production behaviour under test.
# Regression test for https://github.com/AikidoSec/firewall-ruby/issues/357.
StreamsController.class_eval do
  def new_controller_thread
    Thread.new { yield }.join
  end
end

class StreamingTest < ActionDispatch::IntegrationTest
  test "streaming action runs in its own thread" do
    get "/streams"

    assert_response :success
    assert_equal "data: ok\n\n", response.body
  end
end
