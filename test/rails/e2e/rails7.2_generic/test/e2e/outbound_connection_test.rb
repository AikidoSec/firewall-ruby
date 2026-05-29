# test/e2e/trigger_test.rb
require "test_helper"
require "net/http"
require "timeout"

class OutboundConnectionTest < ActiveSupport::TestCase
  test "outbound connections are not blocked when outbound connection blocking is not configured" do
    response = Net::HTTP.get_response(URI("http://localhost:3000/test/outbound_connection?domain=aikido.dev"))
    assert_equal "200", response.code
    body = JSON.parse(response.body)
    assert_equal "301", body["status"]
  end
end
