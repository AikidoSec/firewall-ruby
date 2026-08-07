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
  setup do
    Rails.application.load_seed
  end

  test "streaming action runs in its own thread" do
    get "/streams"

    assert_response :success
    assert_equal "data: ok\n\n", response.body
  end

  test "sinks still scan inside the streaming thread" do
    get "/streams/query", params: {token: "abc' OR 1=1--"}

    assert_response :success
    assert_equal "data: Aikido::Zen::SQLInjectionError\n\n", response.body
  end

  test "legitimate queries are not flagged inside the streaming thread" do
    get "/streams/query", params: {token: "abc123"}

    assert_response :success
    assert_equal "data: ok\n\n", response.body
  end
end
