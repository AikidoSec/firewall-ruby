# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::Sinks::CurbTest < ActiveSupport::TestCase
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
