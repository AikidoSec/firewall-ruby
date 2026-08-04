# frozen_string_literal: true

require "test_helper"

class HttpxTest < ActiveSupport::TestCase
  include RailsServerHelpers

  test "successful HTTPX requests go through" do
    response = rails_get("/test/httpx")
    assert_equal "200", response.code

    body = JSON.parse(response.body)
    assert_equal "response", body["result"]
    assert_equal 200, body["status"]
  end

  # See https://github.com/AikidoSec/firewall-ruby/issues/350: the sink used to
  # raise NoMethodError from inside the HTTPX event loop when a request failed
  # before producing a response, masking the underlying error.
  test "HTTPX transport failures surface as an ErrorResponse instead of crashing" do
    response = rails_get("/test/httpx?mode=unreachable")
    assert_equal "200", response.code

    body = JSON.parse(response.body)
    assert_equal "error_response", body["result"]
    assert_equal "HTTPX::ConnectionError", body["error"]
  end
end
