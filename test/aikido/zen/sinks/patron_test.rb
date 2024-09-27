# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::PatronTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    setup do
      stub_request(:get, "https://example.com/safe")
        .to_return(status: 200, body: "OK")

      @outbound_connections = Aikido::Zen.send(:agent).stats.outbound_connections
    end

    test "allows normal requests" do
      refute_attack do
        session = Patron::Session.new(base_url: "https://example.com")
        response = session.get("/safe")
        assert_equal "OK", response.body.to_s
      end

      assert_requested :get, "https://example.com/safe"
    end

    test "prevents requests to hosts that come from user input" do
      set_context_from_request_to "/?host=example.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        session = Patron::Session.new(base_url: "https://example.com")
        session.get("/safe")
      end

      assert_not_requested :get, "https://example.com/safe"
    end

    test "raises a useful error message" do
      set_context_from_request_to "/?host=example.com"

      error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
        session = Patron::Session.new(base_url: "https://example.com")
        session.get("/safe")
      end

      assert_equal \
        "SSRF: Request to user-supplied hostname «example.com» detected in patron.request.",
        error.message
    end

    test "does not log an outbound connection if the request was blocked" do
      set_context_from_request_to "/?host=example.com"

      assert_no_difference -> { @outbound_connections.size } do
        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          session = Patron::Session.new(base_url: "https://example.com")
          session.get("/safe")
        end
      end
    end

    test "prevents requests to redirected domains when the origin is user input" do
      stub_request(:get, "https://example.com")
        .to_return(status: 301, headers: {"Location" => "https://this-is-harmless-i-swear.com/"})
      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        session = Patron::Session.new(base_url: "https://example.com")
        response = session.get("/")
        assert_equal 301, response.status

        redirect_uri = URI(response.headers["location"])
        new_session = Patron::Session.new(base_url: redirect_uri.origin)
        new_session.get(redirect_uri.path)
      end

      assert_requested :get, "https://example.com"
      assert_not_requested :get, "https://this-is-harmless-i-swear.com"
    end

    test "prevents automated requests to redirected domains when the origin is user input" do
      skip <<~REASON.tr("\n", " ")
        We have no way to hook into libcurl's internals from Ruby, so we can't
        actually intercept Patron's internal handling of automatic redirects,
        since they happen in the C layer.
      REASON

      stub_request(:get, "https://example.com")
        .to_return(status: 301, headers: {"Location" => "https://this-is-harmless-i-swear.com/"})
      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        session = Patron::Session.new(base_url: "https://example.com")
        session.get("/", max_redirects: 1)
      end

      assert_requested :get, "https://example.com"
      assert_not_requested :get, "https://this-is-harmless-i-swear.com"
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
