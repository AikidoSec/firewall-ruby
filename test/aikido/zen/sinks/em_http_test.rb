# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::EmHttpRequestTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    setup do
      stub_request(:get, "https://localhost/safe")
        .to_return(status: 200, body: "OK")
    end

    # Makes a request within the EM reactor loop and returns the EM::HTTP object
    def make_request(verb, uri, **options)
      http = nil
      EventMachine.run do
        http = EventMachine::HttpRequest.new(uri).public_send(verb, **options)
        http.callback { EventMachine.stop }
      end
      http
    end

    test "allows normal requests" do
      refute_attack do
        http = make_request(:get, "https://localhost/safe")
        assert_equal "OK", http.response
      end

      assert_requested :get, "https://localhost/safe"
    end

    test "prevents requests to hosts that come from user input" do
      set_context_from_request_to "/?host=localhost"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        make_request(:get, "https://localhost/safe")
      end

      assert_not_requested :get, "https://localhost/safe"
    end

    test "does not fail if a context is not set" do
      Aikido::Zen.current_context = nil

      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "")

      refute_attack do
        make_request(:get, "http://localhost")
      end

      assert_requested :get, "http://localhost"
    end

    test "raises a useful error message" do
      set_context_from_request_to "/?host=localhost"

      error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
        make_request(:get, "https://localhost/safe")
      end

      assert_equal \
        "SSRF: Request to user-supplied hostname «localhost» detected in em-http-request.request (GET https://localhost/safe).",
        error.message
    end

    test "does not log an outbound connection if the request was blocked" do
      set_context_from_request_to "/?host=localhost"

      assert_no_difference "Aikido::Zen.collector.hosts.size" do
        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          make_request(:get, "https://localhost/safe")
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
        http = make_request(:get, "https://this-is-harmless-i-swear.com")
        assert_equal 301, http.response_header.status

        make_request(:get, http.response_header["Location"])
      end

      assert_requested :get, "https://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
    end

    test "prevents automated requests to redirected domains when the origin is user input" do
      skip <<~REASON.tr("\n", " ")
        The way that webmock patches em-http-request hacks around the automatic
        redirection mechanism, preventing our code from actually running in the
        test. For now, this has been tested manually to work. We need to figure
        out how to improve this test.
      REASON

      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        make_request(:get, "https://this-is-harmless-i-swear.com", redirects: 1)
      end

      assert_requested :get, "https://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
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

    # Runs the block within the EM reactor loop. The block must return an EM::HTTP
    # object with request / response information.
    def within_reactor(&block)
      http = nil
      EventMachine.run do
        http = block.call
        http.callback { EventMachine.stop }
      end
      http
    end

    test "tracks HEAD requests made through .head" do
      assert_tracks_outbound_to "example.com", 443 do
        http = within_reactor { EventMachine::HttpRequest.new(@https_uri).head }
        assert_equal 200, http.response_header.status
      end

      assert_tracks_outbound_to "example.com", 80 do
        http = within_reactor { EventMachine::HttpRequest.new(@http_uri).head }
        assert_equal 200, http.response_header.status
      end

      assert_tracks_outbound_to "example.com", 8080 do
        http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).head }
        assert_equal 200, http.response_header.status
      end
    end

    test "tracks GET requests made through .get" do
      assert_tracks_outbound_to "example.com", 443 do
        http = within_reactor { EventMachine::HttpRequest.new(@https_uri).get }
        assert_equal "OK (443)", http.response
      end

      assert_tracks_outbound_to "example.com", 80 do
        http = within_reactor { EventMachine::HttpRequest.new(@http_uri).get }
        assert_equal "OK (80)", http.response
      end

      assert_tracks_outbound_to "example.com", 8080 do
        http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).get }
        assert_equal "OK (8080)", http.response
      end
    end

    test "tracks POST requests made through .post" do
      assert_tracks_outbound_to "example.com", 443 do
        http = within_reactor { EventMachine::HttpRequest.new(@https_uri).post(body: "test") }
        assert_equal "OK (443)", http.response
      end

      assert_tracks_outbound_to "example.com", 80 do
        http = within_reactor { EventMachine::HttpRequest.new(@http_uri).post(body: "test") }
        assert_equal "OK (80)", http.response
      end

      assert_tracks_outbound_to "example.com", 8080 do
        http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).post(body: "test") }
        assert_equal "OK (8080)", http.response
      end
    end

    test "tracks PUT requests made through .put" do
      assert_tracks_outbound_to "example.com", 443 do
        http = within_reactor { EventMachine::HttpRequest.new(@https_uri).put(body: "test") }
        assert_equal "OK (443)", http.response
      end

      assert_tracks_outbound_to "example.com", 80 do
        http = within_reactor { EventMachine::HttpRequest.new(@http_uri).put(body: "test") }
        assert_equal "OK (80)", http.response
      end

      assert_tracks_outbound_to "example.com", 8080 do
        http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).put(body: "test") }
        assert_equal "OK (8080)", http.response
      end
    end

    test "tracks PATCH requests made through .patch" do
      assert_tracks_outbound_to "example.com", 443 do
        http = within_reactor { EventMachine::HttpRequest.new(@https_uri).patch(body: "test") }
        assert_equal "OK (443)", http.response
      end

      assert_tracks_outbound_to "example.com", 80 do
        http = within_reactor { EventMachine::HttpRequest.new(@http_uri).patch(body: "test") }
        assert_equal "OK (80)", http.response
      end

      assert_tracks_outbound_to "example.com", 8080 do
        http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).patch(body: "test") }
        assert_equal "OK (8080)", http.response
      end
    end

    test "tracks DELETE requests made through .delete" do
      assert_tracks_outbound_to "example.com", 443 do
        http = within_reactor { EventMachine::HttpRequest.new(@https_uri).delete }
        assert_equal "OK (443)", http.response
      end

      assert_tracks_outbound_to "example.com", 80 do
        http = within_reactor { EventMachine::HttpRequest.new(@http_uri).delete }
        assert_equal "OK (80)", http.response
      end

      assert_tracks_outbound_to "example.com", 8080 do
        http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).delete }
        assert_equal "OK (8080)", http.response
      end
    end

    test "tracks OPTIONS requests made through .options" do
      assert_tracks_outbound_to "example.com", 443 do
        http = within_reactor { EventMachine::HttpRequest.new(@https_uri).options }
        assert_equal "OK (443)", http.response
      end

      assert_tracks_outbound_to "example.com", 80 do
        http = within_reactor { EventMachine::HttpRequest.new(@http_uri).options }
        assert_equal "OK (80)", http.response
      end

      assert_tracks_outbound_to "example.com", 8080 do
        http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).options }
        assert_equal "OK (8080)", http.response
      end
    end
  end
end
