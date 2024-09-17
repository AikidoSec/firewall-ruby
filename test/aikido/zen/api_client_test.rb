# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::APIClientTest < ActiveSupport::TestCase
  setup do
    @client = Aikido::Zen::APIClient.new
  end

  test "reports it cannot make requests if the configured token is nil" do
    Aikido::Zen.config.api_token = nil
    refute @client.can_make_requests?
  end

  test "reports it cannot make requests if the configured token is empty" do
    Aikido::Zen.config.api_token = ""
    refute @client.can_make_requests?
  end

  test "reports it can make requests if the configured token is present" do
    Aikido::Zen.config.api_token = "TOKEN"
    assert @client.can_make_requests?
  end

  # The HTTP Request scanner is triggering scans, and reporting on outbound
  # connections, which due to how the Agent works, automatically starts the
  # Runner, which tries to make other HTTP requests (like reporting a start
  # event), that this test doesn't care about.
  #
  # This avoids this by replacing the Aikido::Zen methods by NOOP calls.
  #
  # FIXME: Make this easier to stub.
  module DisableAgentReporting
    def self.included(base)
      original_agent_interface = {
        track_scan: Aikido::Zen.method(:track_scan),
        track_outbound: Aikido::Zen.method(:track_outbound)
      }

      base.setup do
        original_agent_interface.each_key do |method|
          Aikido::Zen.singleton_class.remove_method(method)
          Aikido::Zen.singleton_class.define_method(method, NOOP)
        end
      end

      base.teardown do
        original_agent_interface.each do |method, implementation|
          Aikido::Zen.singleton_class.remove_method(method)
          Aikido::Zen.singleton_class.define_method(method, implementation)
        end
      end
    end
  end

  class CheckIfStaleConfigTest < ActiveSupport::TestCase
    include DisableAgentReporting

    setup do
      Aikido::Zen.config.api_token = "TOKEN"
      Aikido::Zen.runtime_settings.updated_at = Time.at(0)

      @client = Aikido::Zen::APIClient.new
    end

    test "returns false without making a request if the token is missing" do
      Aikido::Zen.config.api_token = nil

      assert_not @client.should_fetch_settings?
      assert_not_requested :get, "https://runtime.aikido.dev/config"
    end

    test "returns true without making a request if we don't know the last update time" do
      assert @client.should_fetch_settings?(nil)
      assert_not_requested :get, "https://runtime.aikido.dev/config"

      Aikido::Zen.runtime_settings.updated_at = nil
      assert @client.should_fetch_settings?
      assert_not_requested :get, "https://runtime.aikido.dev/config"
    end

    test "returns false if the updated_at from the server is the same or older than the one we have" do
      stub_request(:get, "https://runtime.aikido.dev/config")
        .to_return(status: 200, body: JSON.dump(configUpdatedAt: 1234567890000))

      Aikido::Zen.runtime_settings.updated_at = Time.at(1234567890)
      assert_not @client.should_fetch_settings?

      Aikido::Zen.runtime_settings.updated_at = Time.at(1234567890 + 1)
      assert_not @client.should_fetch_settings?
    end

    test "returns true if the updated_at from the server is newer than the one we have" do
      stub_request(:get, "https://runtime.aikido.dev/config")
        .to_return(status: 200, body: JSON.dump(configUpdatedAt: 1234567890000))

      Aikido::Zen.runtime_settings.updated_at = Time.at(1234567890 - 1)
      assert @client.should_fetch_settings?
    end

    test "sets the User-Agent on the request" do
      stub_request(:get, "https://runtime.aikido.dev/config")
        .to_return(status: 200, body: JSON.dump(configUpdatedAt: 1234567890000))

      @client.should_fetch_settings?

      assert_requested :get, "https://runtime.aikido.dev/config",
        headers: {"User-Agent" => "firewall-ruby v#{Aikido::Zen::VERSION}"}
    end

    test "raises Aikido::Zen::APIError on 4XX requests" do
      stub_request(:get, "https://runtime.aikido.dev/config")
        .to_return(status: 401, body: "")

      err = assert_raises Aikido::Zen::APIError do
        @client.should_fetch_settings?
      end

      assert 401, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "raises Aikido::Zen::APIError on 5XX requests" do
      stub_request(:get, "https://runtime.aikido.dev/config")
        .to_return(status: 502, body: "")

      err = assert_raises Aikido::Zen::APIError do
        @client.should_fetch_settings?
      end

      assert 502, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "wraps timeouts in Aikido::Zen::NetworkError" do
      stub_request(:get, "https://runtime.aikido.dev/config")
        .to_timeout

      err = assert_raises Aikido::Zen::NetworkError do
        @client.should_fetch_settings?
      end

      assert_kind_of Timeout::Error, err.cause
    end

    test "logs a debug message" do
      stub_request(:get, "https://runtime.aikido.dev/config")
        .to_return(status: 200, body: JSON.dump(configUpdatedAt: 1234567890))

      @client.should_fetch_settings?

      assert_logged :debug, /polling for new runtime settings/i
    end
  end

  class FetchingConfigTest < ActiveSupport::TestCase
    include DisableAgentReporting

    setup do
      Aikido::Zen.config.api_token = "TOKEN"
      @client = Aikido::Zen::APIClient.new
    end

    test "makes a GET request to the specified endpoint" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      response = @client.fetch_settings
      assert response["success"]

      assert_requested :get, "https://guard.aikido.dev/api/runtime/config",
        headers: {
          "Authorization" => Aikido::Zen.config.api_token,
          "Accept" => "application/json"
        }
    end

    test "uses the host configured in the agent config" do
      Aikido::Zen.config.api_base_url = "https://test.aikido.dev"

      stub_request(:get, "https://test.aikido.dev/api/runtime/config")
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      response = @client.fetch_settings
      assert response["success"]

      assert_requested :get, "https://test.aikido.dev/api/runtime/config",
        headers: {
          "Authorization" => Aikido::Zen.config.api_token,
          "Accept" => "application/json"
        }
    end

    test "sets the User-Agent on the request" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      @client.fetch_settings

      assert_requested :get, "https://guard.aikido.dev/api/runtime/config",
        headers: {"User-Agent" => "firewall-ruby v#{Aikido::Zen::VERSION}"}
    end

    test "raises Aikido::Zen::APIError on 4XX requests" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 401, body: "")

      err = assert_raises Aikido::Zen::APIError do
        @client.fetch_settings
      end

      assert 401, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "raises Aikido::Zen::APIError on 5XX requests" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 502, body: "")

      err = assert_raises Aikido::Zen::APIError do
        @client.fetch_settings
      end

      assert 502, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "wraps timeouts in Aikido::Zen::NetworkError" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_timeout

      err = assert_raises Aikido::Zen::NetworkError do
        @client.fetch_settings
      end

      assert_kind_of Timeout::Error, err.cause
    end

    test "logs a debug message" do
      stub_request(:get, "https://guard.aikido.dev/api/runtime/config")
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      @client.fetch_settings

      assert_logged :debug, /fetching new runtime settings/i
    end
  end

  class ReportStartedEvent < ActiveSupport::TestCase
    include DisableAgentReporting

    setup do
      Aikido::Zen.config.api_token = "TOKEN"
      @client = Aikido::Zen::APIClient.new
    end

    test "makes a POST request to the specified endpoint" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .with(body: hash_including(type: "started"))
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      response = @client.report(Aikido::Zen::Events::Started.new)
      assert response["success"]

      assert_requested :post, "https://guard.aikido.dev/api/runtime/events",
        headers: {
          "Authorization" => Aikido::Zen.config.api_token,
          "Accept" => "application/json",
          "Content-Type" => "application/json"
        },
        body: hash_including(type: "started")
    end

    test "it sends the timestamp of the event in milliseconds" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .with(body: hash_including(type: "started"))
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      event = Aikido::Zen::Events::Started.new(time: Time.at(1234567890))
      @client.report(event)

      assert_requested :post, "https://guard.aikido.dev/api/runtime/events",
        body: hash_including(
          type: "started",
          time: 1234567890000
        )
    end

    test "it sends the agent info" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .with(body: hash_including(type: "started"))
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      @client.report(Aikido::Zen::Events::Started.new)

      assert_requested :post, "https://guard.aikido.dev/api/runtime/events",
        body: hash_including(
          type: "started",
          agent: Aikido::Zen.system_info.as_json
        )
    end

    test "uses the host configured in the agent config" do
      Aikido::Zen.config.api_base_url = "https://app.local.aikido.io"

      stub_request(:post, "https://app.local.aikido.io/api/runtime/events")
        .with(body: hash_including(type: "started"))
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      @client.report(Aikido::Zen::Events::Started.new)

      assert_requested :post, "https://app.local.aikido.io/api/runtime/events"
    end

    test "sets the User-Agent on the request" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .with(body: hash_including(type: "started"))
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      @client.report(Aikido::Zen::Events::Started.new)

      assert_requested :post, "https://guard.aikido.dev/api/runtime/events",
        headers: {"User-Agent" => "firewall-ruby v#{Aikido::Zen::VERSION}"}
    end

    test "logs an error and skips making a request if the rate limiter decides to throttle" do
      rate_limiter = Minitest::Mock.new
      rate_limiter.expect :throttle?, true, [Aikido::Zen::Event]

      @client = Aikido::Zen::APIClient.new(rate_limiter: rate_limiter)
      assert_nil @client.report(Aikido::Zen::Events::Started.new)

      assert_logged :error, /Not reporting STARTED event due to rate limiting/
      assert_not_requested :post, "https://guard.aikido.dev/api/runtime/events"
      assert_mock rate_limiter
    end

    test "raises Aikido::Zen::APIError on 4XX requests" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .to_return(status: 401, body: "")

      err = assert_raises Aikido::Zen::APIError do
        @client.report(Aikido::Zen::Events::Started.new)
      end

      assert 401, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "trips open the rate limiter on 429 requests" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .to_return(status: 429, body: "")

      circuit_breaker = @client.instance_variable_get(:@rate_limiter)
      refute circuit_breaker.open?

      err = assert_raises Aikido::Zen::APIError do
        @client.report(Aikido::Zen::Events::Started.new)
      end

      assert circuit_breaker.open?
      assert 429, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "raises Aikido::Zen::APIError on 5XX requests" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .to_return(status: 502, body: "")

      err = assert_raises Aikido::Zen::APIError do
        @client.report(Aikido::Zen::Events::Started.new)
      end

      assert 502, err.response.code
      assert "********************OKEN", err.request["Authorization"]
    end

    test "wraps timeouts in Aikido::Zen::NetworkError" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .to_timeout

      err = assert_raises Aikido::Zen::NetworkError do
        @client.report(Aikido::Zen::Events::Started.new)
      end

      assert_kind_of Timeout::Error, err.cause
    end

    test "logs a debug message" do
      stub_request(:post, "https://guard.aikido.dev/api/runtime/events")
        .with(body: hash_including(type: "started"))
        .to_return(status: 200, body: file_fixture("api_responses/fetch_settings.success.json"))

      @client.report(Aikido::Zen::Events::Started.new)

      assert_logged :debug, /reporting started event/i
    end
  end
end
