# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::Sinks::PatronTest < ActiveSupport::TestCase
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
