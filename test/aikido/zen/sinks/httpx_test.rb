# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::HTTPXTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include HTTPConnectionTrackingAssertions

  setup do
    @https_uri = URI("https://example.com/path")
    @http_uri = URI("http://example.com/path")
    @custom_port_uri = URI("http://example.com:8080/path")

    stub_http_request(:any, @https_uri).to_return(status: 200, body: "OK (443)")
    stub_http_request(:any, @http_uri).to_return(status: 200, body: "OK (80)")
    stub_http_request(:any, @custom_port_uri).to_return(status: 200, body: "OK (8080)")
  end

  test "tracks GET requests made through .get" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.get(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.get(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.get(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks POST requests made through .post" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.post(@https_uri, body: "test")
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.post(@http_uri, body: "test")
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.post(@custom_port_uri, body: "test")
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks PUT requests made through .put" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.put(@https_uri, body: "test")
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.put(@http_uri, body: "test")
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.put(@custom_port_uri, body: "test")
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks PATCH requests made through .patch" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.patch(@https_uri, body: "test")
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.patch(@http_uri, body: "test")
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.patch(@custom_port_uri, body: "test")
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks DELETE requests made through .delete" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.delete(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.delete(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.delete(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks OPTIONS requests made through .options" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.options(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.options(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.options(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks TRACE requests made through .trace" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.trace(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.trace(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.trace(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks CONNECT requests made through .connect" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTPX.connect(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTPX.connect(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTPX.connect(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end
end
