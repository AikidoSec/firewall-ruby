# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::HTTPTest < ActiveSupport::TestCase
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
      response = HTTP.get(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.get(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.get(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks POST requests made through .post" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTP.post(@https_uri, body: "test")
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.post(@http_uri, body: "test")
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.post(@custom_port_uri, body: "test")
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks PUT requests made through .put" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTP.put(@https_uri, body: "test")
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.put(@http_uri, body: "test")
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.put(@custom_port_uri, body: "test")
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks PATCH requests made through .patch" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTP.patch(@https_uri, body: "test")
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.patch(@http_uri, body: "test")
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.patch(@custom_port_uri, body: "test")
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks DELETE requests made through .delete" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTP.delete(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.delete(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.delete(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks OPTIONS requests made through .options" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTP.options(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.options(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.options(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks TRACE requests made through .trace" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTP.trace(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.trace(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.trace(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end

  test "tracks CONNECT requests made through .connect" do
    assert_tracks_outbound_to "example.com", 443 do
      response = HTTP.connect(@https_uri)
      assert_equal "OK (443)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = HTTP.connect(@http_uri)
      assert_equal "OK (80)", response.body.to_s
    end

    assert_tracks_outbound_to "example.com", 8080 do
      response = HTTP.connect(@custom_port_uri)
      assert_equal "OK (8080)", response.body.to_s
    end
  end
end
