# frozen_string_literal: true

# Async::HTTP only supports ruby 3.1+
return if RUBY_VERSION < "3.1"

require "test_helper"
require "async/http/middleware/location_redirector"

class Aikido::Zen::Sinks::AsyncHTTPTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

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

    test "raises a useful error message" do
      Sync do
        set_context_from_request_to "/?host=localhost"

        error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
          client = Async::HTTP::Internet.new
          client.get(URI("https://localhost/safe"))
        end

        assert_equal \
          "SSRF: Request to user-supplied hostname «localhost» detected in async-http.request (GET https://localhost/safe).",
          error.message
      end
    end

    test "does not log an outbound connection if the request was blocked" do
      Sync do
        set_context_from_request_to "/?host=localhost"

        assert_no_difference "Aikido::Zen.collector.hosts.size" do
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
end
