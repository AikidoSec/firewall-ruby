require "test_helper"

class RequestBypassingTest < ActionDispatch::IntegrationTest
  setup do
    Aikido::Zen.runtime_settings.update_from_runtime_config_json(
      "endpoints" => [{
        "method" => "GET",
        "route" => "/test/rate_limit(.:format)",
        "rateLimiting" => {
          "enabled" => true,
          "maxRequests" => 2,
          "windowSizeInMS" => 60_000
        }
      }]
    )
  end

  test "requests are rate limited normally" do
    get "/test/rate_limit"
    assert_response :success

    get "/test/rate_limit"
    assert_response :success

    get "/test/rate_limit"
    assert_response :too_many_requests
  end

  test "requests bypassed via Aikido::Zen.request_bypassed! are not rate limited" do
    headers = {"X-Bypass-Zen" => "true"}

    4.times do
      get "/test/rate_limit", headers: headers
      assert_response :success
    end
  end
end
