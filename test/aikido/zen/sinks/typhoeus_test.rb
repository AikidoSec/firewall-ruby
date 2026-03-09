# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::TyphoeusTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers
    include HTTPConnectionTrackingAssertions

    setup do
      stub_request(:get, "https://localhost/safe")
        .to_return(status: 200, body: "OK")
    end

    test "allows normal requests" do
      refute_attack do
        response = Typhoeus.get("https://localhost/safe")
        assert_equal "OK", response.body
      end

      assert_requested :get, "https://localhost/safe"
    end

    test "does not fail if a context is not set" do
      Aikido::Zen.current_context = nil

      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "")

      refute_attack do
        Typhoeus.get("http://localhost")
      end

      assert_requested :get, "http://localhost"
    end

    test "prevents requests to hosts that come from user input" do
      set_context_from_request_to "/?host=localhost"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Typhoeus.get("https://localhost/safe")
      end

      assert_not_requested :get, "https://localhost/safe"
    end

    test "logs an outbound connection even if the request was blocked" do
      set_context_from_request_to "/?host=localhost"

      assert_tracks_outbound_to("localhost", 443) do
        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          Typhoeus.get("https://localhost/safe")
        end
      end
    end

    test "prevents requests to redirected domains when the origin is user input" do
      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        response = Typhoeus.get("https://this-is-harmless-i-swear.com")
        assert_equal 301, response.code

        Typhoeus.get(response.headers["Location"])
      end

      assert_requested :get, "https://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
    end

    test "prevents automated requests to redirected domains when the origin is user input" do
      skip <<~REASON.tr("\n", " ")
        Typhoeus' WebMock adapter does not support Typhoeus's "followlocation"
        key, so although the feature works / has been tested manually, we can't
        write an automated test for it.

        See https://github.com/bblimke/webmock/issues/1071
      REASON

      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Typhoeus.get("https://this-is-harmless-i-swear.com", followlocation: true)
      end

      assert_requested :get, "https://this-is-harmless-i-swear.com"

      # With libcurl wrappers, we can't stop the problematic request from
      # happening, but we can stop the attacker from getting the response.
      assert_requested :get, "http://localhost"
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
    end

    class EasyTest < self
      test "tracks GET requests made through .get" do
        assert_tracks_outbound_to "example.com", 443 do
          response = Typhoeus.get(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = Typhoeus.get(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = Typhoeus.get(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks POST requests made through .post" do
        assert_tracks_outbound_to "example.com", 443 do
          response = Typhoeus.post(@https_uri, body: "test")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = Typhoeus.post(@http_uri, body: "test")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = Typhoeus.post(@custom_port_uri, body: "test")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks PUT requests made through .put" do
        assert_tracks_outbound_to "example.com", 443 do
          response = Typhoeus.put(@https_uri, body: "test")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = Typhoeus.put(@http_uri, body: "test")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = Typhoeus.put(@custom_port_uri, body: "test")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks PATCH requests made through .patch" do
        assert_tracks_outbound_to "example.com", 443 do
          response = Typhoeus.patch(@https_uri, body: "test")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = Typhoeus.patch(@http_uri, body: "test")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = Typhoeus.patch(@custom_port_uri, body: "test")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks DELETE requests made through .delete" do
        assert_tracks_outbound_to "example.com", 443 do
          response = Typhoeus.delete(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = Typhoeus.delete(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = Typhoeus.delete(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks OPTIONS requests made through .options" do
        assert_tracks_outbound_to "example.com", 443 do
          response = Typhoeus.options(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = Typhoeus.options(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = Typhoeus.options(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end
    end

    class HydraTest < self
      setup { @hydra = Typhoeus::Hydra.new }

      test "tracks HEAD requests made through Hydra" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :head)
          @hydra.queue(request)
          @hydra.run
          assert_equal 200, request.response.code
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :head)
          @hydra.queue(request)
          @hydra.run
          assert_equal 200, request.response.code
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :head)
          @hydra.queue(request)
          @hydra.run
          assert_equal 200, request.response.code
        end
      end

      test "tracks GET requests made through Hydra" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :get)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :get)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :get)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
        end
      end

      test "tracks POST requests made through #post" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :post, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :post, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :post, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
        end
      end

      test "tracks PUT requests made through #put" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :put, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :put, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :put, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
        end
      end

      test "tracks PATCH requests made through #patch" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :patch, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :patch, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :patch, body: "test")
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
        end
      end

      test "tracks DELETE requests made through #delete" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :delete)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :delete)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :delete)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
        end
      end

      test "tracks OPTIONS requests made through #options" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :options)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :options)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :options)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
        end
      end

      test "tracks TRACE requests made through #trace" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :trace)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :trace)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :trace)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
        end
      end

      test "tracks CONNECT requests made through #connect" do
        assert_tracks_outbound_to "example.com", 443 do
          request = Typhoeus::Request.new(@https_uri, method: :connect)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (443)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          request = Typhoeus::Request.new(@http_uri, method: :connect)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (80)", request.response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          request = Typhoeus::Request.new(@custom_port_uri, method: :connect)
          @hydra.queue(request)
          @hydra.run
          assert_equal "OK (8080)", request.response.body
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
      response = Typhoeus.get(@safe_uri)
      assert_equal "OK (80)", response.body

      response = Typhoeus.get(@evil_uri)
      assert_equal "OK (80)", response.body

      response = Typhoeus.get(@new_uri)
      assert_equal "OK (80)", response.body
    end

    test "all requests are allowed when blockNewOutgoingRequests is false and the domain list is empty" do
      configure_domains(block_new_outbound: false, domains: [])

      response = Typhoeus.get(@safe_uri)
      assert_equal "OK (80)", response.body

      response = Typhoeus.get(@evil_uri)
      assert_equal "OK (80)", response.body

      response = Typhoeus.get(@new_uri)
      assert_equal "OK (80)", response.body
    end

    test "all requests are blocked when blockNewOutgoingRequests is true and the domain list is empty" do
      configure_domains(block_new_outbound: true, domains: [])

      assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
        response = Typhoeus.get(@safe_uri)
        assert_equal "OK (80)", response.body
      end

      assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
        response = Typhoeus.get(@evil_uri)
        assert_equal "OK (80)", response.body
      end

      assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
        response = Typhoeus.get(@new_uri)
        assert_equal "OK (80)", response.body
      end
    end

    test "requests to allowed domains are allowed when blockNewOutgoingRequests is true" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS)

      response = Typhoeus.get(@safe_uri)
      assert_equal "OK (80)", response.body
    end

    test "requests to blocked domains are blocked when blockNewOutgoingRequests is true" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS)

      assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
        response = Typhoeus.get(@evil_uri)
        assert_equal "OK (80)", response.body
      end
    end

    test "requests to unknown domains are blocked when blockNewOutgoingRequests is true" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS)

      assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
        response = Typhoeus.get(@new_uri)
        assert_equal "OK (80)", response.body
      end
    end

    test "requests to allowed domains are allowed when blockNewOutgoingRequests is false" do
      configure_domains(block_new_outbound: false, domains: DEFAULT_DOMAINS)

      response = Typhoeus.get(@safe_uri)
      assert_equal "OK (80)", response.body
    end

    test "requests to blocked domains are blocked when blockNewOutgoingRequests is false" do
      configure_domains(block_new_outbound: false, domains: DEFAULT_DOMAINS)

      assert_raises(Aikido::Zen::OutboundConnectionBlockedError) do
        response = Typhoeus.get(@evil_uri)
        assert_equal "OK (80)", response.body
      end
    end

    test "requests to unknown domains are allowed when blockNewOutgoingRequests is false" do
      configure_domains(block_new_outbound: false, domains: DEFAULT_DOMAINS)

      response = Typhoeus.get(@new_uri)
      assert_equal "OK (80)", response.body
    end

    test "all requests are allowed when the client IP is in the bypassed IPs list" do
      configure_domains(block_new_outbound: true, domains: DEFAULT_DOMAINS, bypassed_ips: ["1.2.3.4"])

      response = Typhoeus.get(@safe_uri)
      assert_equal "OK (80)", response.body

      response = Typhoeus.get(@evil_uri)
      assert_equal "OK (80)", response.body

      response = Typhoeus.get(@new_uri)
      assert_equal "OK (80)", response.body
    end
  end
end
