# frozen_string_literal: true

require "test_helper"

class OutboundConnectionTest < ActiveSupport::TestCase
  include RailsServerHelpers

  test "outbound connections are not blocked when outbound connection blocking is not configured" do
    response = rails_get("/test/outbound_connection?domain=aikido.dev")
    assert_equal "200", response.code
    body = JSON.parse(response.body)
    assert_equal "301", body["status"]
  end
end
