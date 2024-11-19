# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::PatronTest < ActiveSupport::TestCase
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
        session = Patron::Session.new(base_url: "https://localhost")
        response = session.get("/safe")
        assert_equal "OK", response.body.to_s
      end

      assert_requested :get, "https://localhost/safe"
    end

    test "prevents requests to hosts that come from user input" do
      set_context_from_request_to "/?host=localhost"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        session = Patron::Session.new(base_url: "https://localhost")
        session.get("/safe")
      end

      assert_not_requested :get, "https://localhost/safe"
    end

    test "does not fail if a context is not set" do
      Aikido::Zen.current_context = nil

      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "")

      refute_attack do
        session = Patron::Session.new(base_url: "http://localhost")
        session.get("/")
      end

      assert_requested :get, "http://localhost"
    end

    test "raises a useful error message" do
      set_context_from_request_to "/?host=localhost"

      error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
        session = Patron::Session.new(base_url: "https://localhost")
        session.get("/safe")
      end

      assert_equal \
        "SSRF: Request to user-supplied hostname «localhost» detected in patron.request (GET https://localhost/safe).",
        error.message
    end

    test "does not log an outbound connection if the request was blocked" do
      set_context_from_request_to "/?host=localhost"

      refute_outbound_connection_to("localhost", 443) do
        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          session = Patron::Session.new(base_url: "https://localhost")
          session.get("/safe")
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
        session = Patron::Session.new(base_url: "https://this-is-harmless-i-swear.com")
        response = session.get("/")
        assert_equal 301, response.status

        redirect_uri = URI(response.headers["location"])
        new_session = Patron::Session.new(base_url: redirect_uri.origin)
        new_session.get(redirect_uri.path)
      end

      assert_requested :get, "https://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
    end

    test "prevents automated requests to redirected domains when the origin is user input" do
      skip <<~REASON.tr("\n", " ")
        Patron's WebMock adapter does not support Patron's "max_redirects" key,
        so although the feature works / has been tested manually, we can't write
        an automated test for it.

        See https://github.com/bblimke/webmock/issues/1071
      REASON

      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        session = Patron::Session.new(base_url: "https://this-is-harmless-i-swear.com")
        session.get("/", max_redirects: 1)
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
        session = Patron::Session.new(base_url: @https_uri.origin)
        response = session.get(@https_uri.path)
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        session = Patron::Session.new(base_url: @http_uri.origin)
        response = session.get(@http_uri.path)
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        session = Patron::Session.new(base_url: @custom_port_uri.origin)
        response = session.get(@custom_port_uri.path)
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks POST requests made through .post" do
      assert_tracks_outbound_to "example.com", 443 do
        session = Patron::Session.new(base_url: @https_uri.origin)
        response = session.post(@https_uri.path, "test")
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        session = Patron::Session.new(base_url: @http_uri.origin)
        response = session.post(@http_uri.path, "test")
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        session = Patron::Session.new(base_url: @custom_port_uri.origin)
        response = session.post(@custom_port_uri.path, "test")
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks PUT requests made through .put" do
      assert_tracks_outbound_to "example.com", 443 do
        session = Patron::Session.new(base_url: @https_uri.origin)
        response = session.put(@https_uri.path, "test")
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        session = Patron::Session.new(base_url: @http_uri.origin)
        response = session.put(@http_uri.path, "test")
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        session = Patron::Session.new(base_url: @custom_port_uri.origin)
        response = session.put(@custom_port_uri.path, "test")
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks PATCH requests made through .patch" do
      assert_tracks_outbound_to "example.com", 443 do
        session = Patron::Session.new(base_url: @https_uri.origin)
        response = session.patch(@https_uri.path, "test")
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        session = Patron::Session.new(base_url: @http_uri.origin)
        response = session.patch(@http_uri.path, "test")
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        session = Patron::Session.new(base_url: @custom_port_uri.origin)
        response = session.patch(@custom_port_uri.path, "test")
        assert_equal "OK (8080)", response.body.to_s
      end
    end

    test "tracks DELETE requests made through .delete" do
      assert_tracks_outbound_to "example.com", 443 do
        session = Patron::Session.new(base_url: @https_uri.origin)
        response = session.delete(@https_uri.path)
        assert_equal "OK (443)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 80 do
        session = Patron::Session.new(base_url: @http_uri.origin)
        response = session.delete(@http_uri.path)
        assert_equal "OK (80)", response.body.to_s
      end

      assert_tracks_outbound_to "example.com", 8080 do
        session = Patron::Session.new(base_url: @custom_port_uri.origin)
        response = session.delete(@custom_port_uri.path)
        assert_equal "OK (8080)", response.body.to_s
      end
    end
  end
end
