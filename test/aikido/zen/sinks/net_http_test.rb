# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::NetHTTPTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    setup do
      stub_request(:get, "https://localhost/safe")
        .to_return(status: 200, body: "OK")
    end

    test "allows normal requests" do
      refute_attack do
        response = Net::HTTP.get(URI("https://localhost/safe"))
        assert_equal "OK", response
      end

      assert_requested :get, "https://localhost/safe"
    end

    test "prevents requests to hosts that come from user input" do
      set_context_from_request_to "/?host=localhost"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Net::HTTP.get(URI("https://localhost/safe"))
      end

      assert_not_requested :get, "https://localhost/safe"
    end

    test "does not fail if a context is not set" do
      Aikido::Zen.current_context = nil

      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "")

      refute_attack do
        Net::HTTP.get(URI("http://localhost"))
      end

      assert_requested :get, "http://localhost"
    end

    test "prevents requests to hosts using the session API" do
      set_context_from_request_to "/?host=localhost"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Net::HTTP.start("localhost", use_ssl: true) do |http|
          http.get("/safe")
        end
      end

      assert_not_requested :get, "https://localhost/safe"
    end

    test "raises a useful error message" do
      set_context_from_request_to "/?host=localhost"

      error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
        Net::HTTP.get(URI("https://localhost/safe"))
      end

      assert_equal \
        "SSRF: Request to user-supplied hostname «localhost» detected in net-http.request (GET https://localhost/safe).",
        error.message
    end

    test "does not log an outbound connection if the request was blocked" do
      set_context_from_request_to "/?host=localhost"

      assert_no_difference "Aikido::Zen.collector.hosts.size" do
        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          Net::HTTP.get(URI("https://localhost/safe"))
        end
      end
    end

    test "prevents requests to redirected domains after if the origin is user input" do
      stub_request(:get, "https://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        response = Net::HTTP.get_response(URI("https://this-is-harmless-i-swear.com"))
        assert_equal "301", response.code

        Net::HTTP.get(URI(response["Location"]))
      end

      assert_requested :get, "https://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
    end
  end

  class ConnectionTrackingTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include HTTPConnectionTrackingAssertions

    setup do
      @http_uri = URI("http://example.com/path")
      @https_uri = URI("https://example.com/path")
      @custom_port_uri = URI("http://example.com:8080/path")

      stub_request(:any, @http_uri).to_return(status: 200, body: "OK (80)")
      stub_request(:any, @https_uri).to_return(status: 200, body: "OK (443)")
      stub_request(:any, @custom_port_uri).to_return(status: 200, body: "OK (8080)")
    end

    test "tracks GET requests made through .get" do
      assert_tracks_outbound_to "example.com", 443 do
        assert_equal "OK (443)", Net::HTTP.get(@https_uri)
      end

      assert_tracks_outbound_to "example.com", 80 do
        assert_equal "OK (80)", Net::HTTP.get(@http_uri)
      end

      assert_tracks_outbound_to "example.com", 8080 do
        assert_equal "OK (8080)", Net::HTTP.get(@custom_port_uri)
      end
    end

    test "tracks GET requests made through .get_response" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Net::HTTP.get_response(@https_uri)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Net::HTTP.get_response(@http_uri)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Net::HTTP.get_response(@custom_port_uri)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks POST requests made through .post" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Net::HTTP.post(@https_uri, "data")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Net::HTTP.post(@http_uri, "data")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Net::HTTP.post(@custom_port_uri, "data")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks POST requests made through .post_form" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Net::HTTP.post_form(@https_uri, "key" => "value")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Net::HTTP.post_form(@http_uri, "key" => "value")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Net::HTTP.post_form(@custom_port_uri, "key" => "value")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks GET requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Get.new(@https_uri.path)
          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.get(@https_uri.path)
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Get.new(@http_uri.path)
          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.get(@http_uri.path)
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Get.new(@custom_port_uri.path)
          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.get(@custom_port_uri.path)
          assert_equal "OK (8080)", response.body
        end
      end
    end

    test "tracks HEAD requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Head.new(@https_uri.path)
          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.head(@https_uri.path)
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Head.new(@http_uri.path)
          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.head(@http_uri.path)
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Head.new(@custom_port_uri.path)
          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.head(@custom_port_uri.path)
          assert_equal "OK (8080)", response.body
        end
      end
    end

    test "tracks POST requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Post.new(@https_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.post(@https_uri.path, "data")
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Post.new(@http_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.post(@http_uri.path, "data")
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Post.new(@custom_port_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.post(@custom_port_uri.path, "data")
          assert_equal "OK (8080)", response.body
        end
      end
    end

    test "tracks PUT requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Put.new(@https_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.put(@https_uri.path, "data")
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Put.new(@http_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.put(@http_uri.path, "data")
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Put.new(@custom_port_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.put(@custom_port_uri.path, "data")
          assert_equal "OK (8080)", response.body
        end
      end
    end

    test "tracks PATCH requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Patch.new(@https_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.patch(@https_uri.path, "data")
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Patch.new(@http_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.patch(@http_uri.path, "data")
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Patch.new(@custom_port_uri.path)
          req.body = "data"

          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.patch(@custom_port_uri.path, "data")
          assert_equal "OK (8080)", response.body
        end
      end
    end

    test "tracks DELETE requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Delete.new(@https_uri.path)
          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.delete(@https_uri.path)
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Delete.new(@http_uri.path)
          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.delete(@http_uri.path)
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Delete.new(@custom_port_uri.path)
          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.delete(@custom_port_uri.path)
          assert_equal "OK (8080)", response.body
        end
      end
    end

    test "tracks OPTIONS requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Options.new(@https_uri.path)
          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.options(@https_uri.path)
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Options.new(@http_uri.path)
          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.options(@http_uri.path)
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Options.new(@custom_port_uri.path)
          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.options(@custom_port_uri.path)
          assert_equal "OK (8080)", response.body
        end
      end
    end

    test "tracks TRACE requests made through #request" do
      assert_tracks_outbound_to "example.com", 443 do
        Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
          req = Net::HTTP::Trace.new(@https_uri.path)
          response = http.request(req)
          assert_equal "OK (443)", response.body

          response = http.trace(@https_uri.path)
          assert_equal "OK (443)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 80 do
        Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
          req = Net::HTTP::Trace.new(@http_uri.path)
          response = http.request(req)
          assert_equal "OK (80)", response.body

          response = http.trace(@http_uri.path)
          assert_equal "OK (80)", response.body
        end
      end

      assert_tracks_outbound_to "example.com", 8080 do
        Net::HTTP.start(@custom_port_uri.hostname, @custom_port_uri.port) do |http|
          req = Net::HTTP::Trace.new(@custom_port_uri.path)
          response = http.request(req)
          assert_equal "OK (8080)", response.body

          response = http.trace(@custom_port_uri.path)
          assert_equal "OK (8080)", response.body
        end
      end
    end
  end
end
