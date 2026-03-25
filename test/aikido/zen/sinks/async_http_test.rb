# frozen_string_literal: true

# Async::HTTP only supports ruby 3.1+
return if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.1")

require "test_helper"
require "async/http/middleware/location_redirector"

class Aikido::Zen::Sinks::AsyncHTTPTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers
    include HTTPConnectionTrackingAssertions

    setup do
      stub_request(:get, "https://localhost/safe")
        .to_return(status: 200, body: "OK")
    end

    test "allows normal requests" do
      Sync do
        refute_attack do
          client = Async::HTTP::Internet.new
          client.get(URI("https://localhost/safe")) do |response|
            assert_equal "OK", response.body.read
          end
        end

        assert_requested :get, "https://localhost/safe"
      end
    end

    test "prevents requests to hosts that come from user input" do
      Sync do
        set_context_from_request_to "/?host=localhost"

        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          client = Async::HTTP::Internet.new
          client.get(URI("https://localhost/safe"))
        end

        assert_not_requested :get, "https://localhost/safe"
      end
    end

    test "does not fail if a context is not set" do
      Sync do
        Aikido::Zen.current_context = nil

        stub_request(:get, "http://localhost/")
          .to_return(status: 200, body: "")

        refute_attack do
          client = Async::HTTP::Internet.new
          client.get(URI("http://localhost"))
        end

        assert_requested :get, "http://localhost"
      end
    end

    test "logs an outbound connection even if the request was blocked" do
      Sync do
        set_context_from_request_to "/?host=localhost"

        assert_tracks_outbound_to("localhost", 443) do
          assert_attack Aikido::Zen::Attacks::SSRFAttack do
            client = Async::HTTP::Internet.new
            client.get(URI("https://localhost/safe"))
          end
        end
      end
    end

    test "prevents requests to redirected domains when the origin is user input" do
      Sync do
        stub_request(:get, "https://this-is-harmless-i-swear.com/")
          .to_return(status: 301, headers: {"Location" => "http://localhost/"})
        stub_request(:get, "http://localhost/")
          .to_return(status: 200, body: "you've been pwnd")

        set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

        client = Async::HTTP::Internet.new

        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          response = client.get(URI("https://this-is-harmless-i-swear.com/"))
          assert_equal 301, response.status

          client.get(URI(response.headers["location"]))
        end

        assert_requested :get, "https://this-is-harmless-i-swear.com"
        assert_not_requested :get, "http://localhost"
      end
    end
  end

  class ConnectionTrackingTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include HTTPConnectionTrackingAssertions

    setup do
      @https_uri = URI("https://example.com/path")
      @http_uri = URI("http://example.com/path")
      @custom_port_uri = URI("http://example.com:8080/path")

      stub_request(:any, @https_uri).to_return(status: 200, body: "OK (443)")
      stub_request(:any, @http_uri).to_return(status: 200, body: "OK (80)")
      stub_request(:any, @custom_port_uri).to_return(status: 200, body: "OK (8080)")

      @client = Async::HTTP::Internet.new
    end

    test "tracks HEAD requests made through .head" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.head(@https_uri) do |response|
            assert_equal 200, response.status
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.head(@http_uri) do |response|
            assert_equal 200, response.status
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.head(@custom_port_uri) do |response|
            assert_equal 200, response.status
          end
        end
      end
    end

    test "tracks GET requests made through .get" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.get(@https_uri) do |response|
            assert_equal "OK (443)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.get(@http_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.get(@custom_port_uri) do |response|
            assert_equal "OK (8080)", response.body.read
          end
        end
      end
    end

    test "tracks POST requests made through .post" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.post(@https_uri, {}, "test") do |response|
            assert_equal "OK (443)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.post(@http_uri, {}, "test") do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.post(@custom_port_uri, {}, "test") do |response|
            assert_equal "OK (8080)", response.body.read
          end
        end
      end
    end

    test "tracks PUT requests made through .put" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.put(@https_uri, {}, "test") do |response|
            assert_equal "OK (443)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.put(@http_uri, {}, "test") do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.put(@custom_port_uri, {}, "test") do |response|
            assert_equal "OK (8080)", response.body.read
          end
        end
      end
    end

    test "tracks PATCH requests made through .patch" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.patch(@https_uri, {}, "test") do |response|
            assert_equal "OK (443)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.patch(@http_uri, {}, "test") do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.patch(@custom_port_uri, {}, "test") do |response|
            assert_equal "OK (8080)", response.body.read
          end
        end
      end
    end

    test "tracks DELETE requests made through .delete" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.delete(@https_uri) do |response|
            assert_equal "OK (443)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.delete(@http_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.delete(@custom_port_uri) do |response|
            assert_equal "OK (8080)", response.body.read
          end
        end
      end
    end

    test "tracks OPTIONS requests made through .options" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.options(@https_uri) do |response|
            assert_equal "OK (443)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.options(@http_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.options(@custom_port_uri) do |response|
            assert_equal "OK (8080)", response.body.read
          end
        end
      end
    end

    test "tracks TRACE requests made through .trace" do
      Sync do
        assert_tracks_outbound_to "example.com", 443 do
          @client.trace(@https_uri) do |response|
            assert_equal "OK (443)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 80 do
          @client.trace(@http_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_tracks_outbound_to "example.com", 8080 do
          @client.trace(@custom_port_uri) do |response|
            assert_equal "OK (8080)", response.body.read
          end
        end
      end
    end
  end

  class ConnectionBlockingTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include HTTPConnectionTrackingAssertions

    # Override StubCurrentContext#current_context to provide a request with an IP
    # necessary for testing bypassed IPs.
    def current_context
      @current_context ||= Aikido::Zen::Context.from_rack_env({
        "REMOTE_ADDR" => "1.2.3.4"
      })
    end

    setup do
      @settings = Aikido::Zen.runtime_settings

      @safe_uri = URI("http://safe.example.com/")
      @evil_uri = URI("http://evil.example.com/")
      @new_uri = URI("http://new.example.com/")

      stub_request(:any, @safe_uri).to_return(status: 200, body: "OK (80)")
      stub_request(:any, @evil_uri).to_return(status: 200, body: "OK (80)")
      stub_request(:any, @new_uri).to_return(status: 200, body: "OK (80)")

      @client = Async::HTTP::Internet.new
    end

    DEFAULT_RUNTIME_CONFIG = {
      "success" => true,
      "serviceId" => 1234,
      "configUpdatedAt" => 1717171717000,
      "heartbeatIntervalInMS" => 60000,
      "endpoints" => [],
      "blockedUserIds" => [],
      "allowedIPAddresses" => [],
      "receivedAnyStats" => false,
      "block" => true
    }

    DEFAULT_DOMAINS = [
      {
        "hostname" => "safe.example.com",
        "mode" => "allow"
      },
      {
        "hostname" => "evil.example.com",
        "mode" => "block"
      }
    ]

    def configure_domains(block_new_outbound: nil, domains: nil, bypassed_ips: [])
      data = DEFAULT_RUNTIME_CONFIG.merge(
        {
          "allowedIPAddresses" => bypassed_ips,
          "blockNewOutgoingRequests" => block_new_outbound,
          "domains" => domains
        }.compact
      )

      @settings.update_from_runtime_config_json(data)
    end

    test "all requests are allowed by default" do
      Sync do
        @client.get(@safe_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end

        @client.get(@evil_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end

        @client.get(@new_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end
      end
    end

    test "all requests are allowed when blockNewOutgoingRequests is false and the domain list is empty" do
      configure_domains(block_new_outbound: false, domains: [])

      Sync do
        @client.get(@safe_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end

        @client.get(@evil_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end

        @client.get(@new_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end
      end
    end

    test "all requests are blocked when blockNewOutgoingRequests is true and the domain list is empty" do
      configure_domains(block_new_outbound: true, domains: [])

      Sync do
        assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
          @client.get(@safe_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
          @client.get(@evil_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end

        assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
          @client.get(@new_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end
      end
    end

    test "requests to allowed domains are allowed when blockNewOutgoingRequests is true" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS)

      Sync do
        @client.get(@safe_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end
      end
    end

    test "requests to blocked domains are blocked when blockNewOutgoingRequests is true" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS)

      Sync do
        assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
          @client.get(@evil_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end
      end
    end

    test "requests to unknown domains are blocked when blockNewOutgoingRequests is true" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS)

      Sync do
        assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
          @client.get(@new_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end
      end
    end

    test "requests to allowed domains are allowed when blockNewOutgoingRequests is false" do
      configure_domains(block_new_outbound: false, domains: DEFAULT_DOMAINS)

      Sync do
        @client.get(@safe_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end
      end
    end

    test "requests to blocked domains are blocked when blockNewOutgoingRequests is false" do
      configure_domains(block_new_outbound: false, domains: DEFAULT_DOMAINS)

      Sync do
        assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
          @client.get(@evil_uri) do |response|
            assert_equal "OK (80)", response.body.read
          end
        end
      end
    end

    test "requests to unknown domains are allowed when blockNewOutgoingRequests is false" do
      configure_domains(block_new_outbound: false, domains: DEFAULT_DOMAINS)

      Sync do
        @client.get(@new_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end
      end
    end

    test "all requests are allowed when the client IP is in the bypassed IPs list" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS, bypassed_ips: ["1.2.3.4"])

      Sync do
        @client.get(@safe_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end

        @client.get(@evil_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end

        @client.get(@new_uri) do |response|
          assert_equal "OK (80)", response.body.read
        end
      end
    end
  end
end
