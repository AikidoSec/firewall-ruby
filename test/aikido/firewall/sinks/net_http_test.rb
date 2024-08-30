# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::Sinks::NetHTTPTest < ActiveSupport::TestCase
  include StubsCurrentContext
  include HTTPConnectionTrackingAssertions

  setup do
    @sink = Aikido::Firewall::Sinks::Net::HTTP::SINK

    @uri = URI("https://example.com/path")

    stub_request(:any, @uri).to_return(status: 200, body: "OK")
  end

  test "tracks GET requests made through .get" do
    assert_tracks_outbound_to "example.com", 443 do
      assert_equal "OK", Net::HTTP.get(@uri)
    end
  end

  test "tracks GET requests made through .get_response" do
    assert_tracks_outbound_to "example.com", 443 do
      response = Net::HTTP.get_response(@uri)
      assert_equal "OK", response.body
    end
  end

  test "tracks POST requests made through .post" do
    assert_tracks_outbound_to "example.com", 443 do
      response = Net::HTTP.post(@uri, "data")
      assert_equal "OK", response.body
    end
  end

  test "tracks POST requests made through .post_form" do
    assert_tracks_outbound_to "example.com", 443 do
      response = Net::HTTP.post_form(@uri, "key" => "value")
      assert_equal "OK", response.body
    end
  end

  test "tracks GET requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Get.new(@uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.get(@uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks HEAD requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Head.new(@uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.head(@uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks POST requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Post.new(@uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.post(@uri.path, "data")
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks PUT requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Put.new(@uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.put(@uri.path, "data")
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks PATCH requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Patch.new(@uri.path)
        req.body = "data"

        response = http.request(req)
        assert_equal "OK", response.body

        response = http.patch(@uri.path, "data")
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks DELETE requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Delete.new(@uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.delete(@uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks OPTIONS requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Options.new(@uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.options(@uri.path)
        assert_equal "OK", response.body
      end
    end
  end

  test "tracks TRACE requests made through #request" do
    assert_tracks_outbound_to "example.com", 443 do
      Net::HTTP.start(@uri.hostname, use_ssl: true) do |http|
        req = Net::HTTP::Trace.new(@uri.path)
        response = http.request(req)
        assert_equal "OK", response.body

        response = http.trace(@uri.path)
        assert_equal "OK", response.body
      end
    end
  end
end
