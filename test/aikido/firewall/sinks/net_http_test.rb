# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::Sinks::NetHTTPTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include HTTPConnectionTrackingAssertions

  setup do
    @sink = Aikido::Firewall::Sinks::Net::HTTP::SINK

    @http_uri = URI("http://example.com/path")
    @https_uri = URI("https://example.com/path")

    stub_request(:any, @http_uri).to_return(status: 200, body: "OK")
    stub_request(:any, @https_uri).to_return(status: 200, body: "OK")
  end

  test "tracks GET requests made through .get" do
    assert_tracks_outbound_to "example.com", 443 do
      assert_equal "OK", Net::HTTP.get(@https_uri)
    end

    assert_tracks_outbound_to "example.com", 80 do
      assert_equal "OK", Net::HTTP.get(@http_uri)
    end
  end

  test "tracks GET requests made through .get_response" do
    assert_tracks_outbound_to "example.com", 443 do
      response = Net::HTTP.get_response(@https_uri)
      assert_equal "OK", response.body
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = Net::HTTP.get_response(@http_uri)
      assert_equal "OK", response.body
    end
  end

  test "tracks POST requests made through .post" do
    assert_tracks_outbound_to "example.com", 443 do
      response = Net::HTTP.post(@https_uri, "data")
      assert_equal "OK", response.body
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = Net::HTTP.post(@http_uri, "data")
      assert_equal "OK", response.body
    end
  end

  test "tracks POST requests made through .post_form" do
    assert_tracks_outbound_to "example.com", 443 do
      response = Net::HTTP.post_form(@https_uri, "key" => "value")
      assert_equal "OK", response.body
    end

    assert_tracks_outbound_to "example.com", 80 do
      response = Net::HTTP.post_form(@http_uri, "key" => "value")
      assert_equal "OK", response.body
    end
  end

  test "tracks GET requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Get.new(@https_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.get(@https_uri.path)
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Get.new(@http_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.get(@http_uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks HEAD requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Head.new(@https_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.head(@https_uri.path)
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Head.new(@http_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.head(@http_uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks POST requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Post.new(@https_uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.post(@https_uri.path, "data")
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Post.new(@http_uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.post(@http_uri.path, "data")
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks PUT requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Put.new(@https_uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.put(@https_uri.path, "data")
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Put.new(@http_uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.put(@http_uri.path, "data")
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks PATCH requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Patch.new(@https_uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.patch(@https_uri.path, "data")
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Patch.new(@http_uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.patch(@http_uri.path, "data")
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks DELETE requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Delete.new(@https_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.delete(@https_uri.path)
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Delete.new(@http_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.delete(@http_uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks OPTIONS requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Options.new(@https_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.options(@https_uri.path)
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Options.new(@http_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.options(@http_uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks TRACE requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@https_uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Trace.new(@https_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.trace(@https_uri.path)
        assert_equal "OK", response.body
      end
    end

    assert_tracks_outbound_to "example.com", 80 do
      Net::HTTP.start(@http_uri.hostname, use_ssl: false) do |http|
        req = Net::HTTP::Trace.new(@http_uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.trace(@http_uri.path)
        assert_equal "OK", response.body
      end
    end
  end
end
