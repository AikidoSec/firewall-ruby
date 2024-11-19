# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::CurbTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    setup do
      stub_request(:get, "https://localhost/safe")
        .to_return(status: 200, body: "OK")
    end

    test "allows normal requests" do
      refute_attack do
        response = Curl.get("https://localhost/safe")
        assert_equal "OK", response.body.to_s
      end

      assert_requested :get, "https://localhost/safe"
    end

    test "prevents requests to hosts that come from user input" do
      set_context_from_request_to "/?host=localhost"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Curl.get("https://localhost/safe")
      end

      assert_not_requested :get, "https://localhost/safe"
    end

    test "does not fail if a context is not set" do
      Aikido::Zen.current_context = nil

      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "")

      refute_attack do
        Curl.get("http://localhost")
      end

      assert_requested :get, "http://localhost"
    end

    test "raises a useful error message" do
      set_context_from_request_to "/?host=localhost"

      error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Curl.get("https://localhost/safe")
      end

      assert_equal \
        "SSRF: Request to user-supplied hostname «localhost» detected in curb.request (https://localhost/safe).",
        error.message
    end

    test "does not log an outbound connection if the request was blocked" do
      set_context_from_request_to "/?host=localhost"

      assert_no_difference "Aikido::Zen.collector.hosts.size" do
        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          Curl.get("https://localhost/safe")
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
        response = Curl.get("https://this-is-harmless-i-swear.com/")
        assert_equal 301, response.status.to_i

        wrapped = Aikido::Zen::Sinks::Curl::Extensions.wrap_response(response)
        Curl.get(wrapped.redirect_to)
      end

      assert_requested :get, "https://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
    end

    test "prevents automated requests to redirected domains when the origin is user input" do
      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Curl.get("https://this-is-harmless-i-swear.com/") do |curl|
          curl.follow_location = true
        end
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

    test "tracks GET requests made through .get" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Curl.get(@https_uri)
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Curl.get(@http_uri)
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Curl.get(@custom_port_uri)
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks .download attempts" do
      assert_tracks_outbound_to "example.com", 443 do
        tempfile = Tempfile.create
        Curl::Easy.download(@https_uri, tempfile.path)
        assert_equal "OK (443)", tempfile.read
      ensure
        FileUtils.rm_f(tempfile.path)
      end

      assert_tracks_outbound_to "example.com", 80 do
        tempfile = Tempfile.create
        Curl::Easy.download(@http_uri, tempfile.path)
        assert_equal "OK (80)", tempfile.read
      ensure
        FileUtils.rm_f(tempfile.path)
      end

      assert_tracks_outbound_to "example.com", 8080 do
        tempfile = Tempfile.create
        Curl::Easy.download(@custom_port_uri, tempfile.path)
        assert_equal "OK (8080)", tempfile.read
      ensure
        FileUtils.rm_f(tempfile.path)
      end
    end

    test "tracks POST requests made through .post" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Curl.post(@https_uri, body: "test")
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Curl.post(@http_uri, body: "test")
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Curl.post(@custom_port_uri, body: "test")
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks PUT requests made through .put" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Curl.put(@https_uri, body: "test")
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Curl.put(@http_uri, body: "test")
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Curl.put(@custom_port_uri, body: "test")
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks PATCH requests made through .patch" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Curl.patch(@https_uri, body: "test")
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Curl.patch(@http_uri, body: "test")
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Curl.patch(@custom_port_uri, body: "test")
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks DELETE requests made through .delete" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Curl.delete(@https_uri)
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Curl.delete(@http_uri)
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Curl.delete(@custom_port_uri)
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks OPTIONS requests made through .options" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Curl.options(@https_uri)
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Curl.options(@http_uri)
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Curl.options(@custom_port_uri)
        assert_equal "OK (8080)", response.body.to_s
      end
    end
  end
end
