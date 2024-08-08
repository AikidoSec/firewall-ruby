# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::APIClientTest < ActiveSupport::TestCase
  setup do
    @client = Aikido::Agent::APIClient.new
  end

  test "reports it cannot make requests if the configured token is nil" do
    Aikido::Agent.config.api_token = nil
    refute @client.can_make_requests?
  end

  test "reports it cannot make requests if the configured token is empty" do
    Aikido::Agent.config.api_token = ""
    refute @client.can_make_requests?
  end

  test "reports it can make requests if the configured token is present" do
    Aikido::Agent.config.api_token = "TOKEN"
    assert @client.can_make_requests?
  end

  class FetchingConfigTest < ActiveSupport::TestCase
    setup do
      Aikido::Agent.config.api_token = "TOKEN"
      @client = Aikido::Agent::APIClient.new
    end

    test "makes a GET request to the specified endpoint" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      response = @client.fetch_settings
      assert response["success"]

      assert_requested :get, "https://guard.aikido.dev/api/runtime/config",
        headers: {
          "Authorization" => Aikido::Agent.config.api_token,
          "Accept" => "application/json"
        }
    end

    test "uses the host configured in the agent config" do
      Aikido::Agent.config.api_base_url = "https://test.aikido.dev"

      stub_request(:get, "https://test.aikido.dev/api/runtime/config")
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      response = @client.fetch_settings
      assert response["success"]

      assert_requested :get, "https://test.aikido.dev/api/runtime/config",
        headers: {
          "Authorization" => Aikido::Agent.config.api_token,
          "Accept" => "application/json"
        }
    end

    test "raises Aikido::Agent::APIError on 4XX requests" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 401, body: "")

      err = assert_raises Aikido::Agent::APIError do
        @client.fetch_settings
      end

      assert 401, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "raises Aikido::Agent::APIError on 5XX requests" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 502, body: "")

      err = assert_raises Aikido::Agent::APIError do
        @client.fetch_settings
      end

      assert 502, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "wraps timeouts in Aikido::Agent::NetworkError" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_timeout

      err = assert_raises Aikido::Agent::NetworkError do
        @client.fetch_settings
      end

      assert_kind_of Timeout::Error, err.cause
    end
  end
end
