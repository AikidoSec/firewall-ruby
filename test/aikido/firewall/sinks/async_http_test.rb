# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::Sinks::AsyncHTTPTest < ActiveSupport::TestCase
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

  # Async::HTTP only supports ruby 3.1+
  if RUBY_VERSION >= "3.1"
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
