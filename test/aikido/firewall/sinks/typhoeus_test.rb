# frozen_string_literal: true

require "test_helper"

class Aikido::Firewall::Sinks::TyphoeusTest < ActiveSupport::TestCase
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

  class EasyTest < self
    test "tracks GET requests made through .get" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Typhoeus.get(@https_uri)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Typhoeus.get(@http_uri)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Typhoeus.get(@custom_port_uri)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks POST requests made through .post" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Typhoeus.post(@https_uri, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Typhoeus.post(@http_uri, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Typhoeus.post(@custom_port_uri, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PUT requests made through .put" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Typhoeus.put(@https_uri, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Typhoeus.put(@http_uri, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Typhoeus.put(@custom_port_uri, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PATCH requests made through .patch" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Typhoeus.patch(@https_uri, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Typhoeus.patch(@http_uri, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Typhoeus.patch(@custom_port_uri, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks DELETE requests made through .delete" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Typhoeus.delete(@https_uri)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Typhoeus.delete(@http_uri)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Typhoeus.delete(@custom_port_uri)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks OPTIONS requests made through .options" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Typhoeus.options(@https_uri)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Typhoeus.options(@http_uri)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Typhoeus.options(@custom_port_uri)
        assert_equal "OK (8080)", response.body
      end
    end
  end

  class HydraTest < self
    setup { @hydra = Typhoeus::Hydra.new }

    test "tracks HEAD requests made through Hydra" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :head)
        @hydra.queue(request)
        @hydra.run
        assert_equal 200, request.response.code
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :head)
        @hydra.queue(request)
        @hydra.run
        assert_equal 200, request.response.code
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :head)
        @hydra.queue(request)
        @hydra.run
        assert_equal 200, request.response.code
      end
    end

    test "tracks GET requests made through Hydra" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :get)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :get)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :get)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end

    test "tracks POST requests made through #post" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :post, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :post, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :post, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end

    test "tracks PUT requests made through #put" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :put, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :put, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :put, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end

    test "tracks PATCH requests made through #patch" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :patch, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :patch, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :patch, body: "test")
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end

    test "tracks DELETE requests made through #delete" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :delete)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :delete)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :delete)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end

    test "tracks OPTIONS requests made through #options" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :options)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :options)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :options)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end

    test "tracks TRACE requests made through #trace" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :trace)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :trace)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :trace)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end

    test "tracks CONNECT requests made through #connect" do
      assert_tracks_outbound_to "example.com", 443 do
        request = Typhoeus::Request.new(@https_uri, method: :connect)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (443)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        request = Typhoeus::Request.new(@http_uri, method: :connect)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (80)", request.response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        request = Typhoeus::Request.new(@custom_port_uri, method: :connect)
        @hydra.queue(request)
        @hydra.run
        assert_equal "OK (8080)", request.response.body
      end
    end
  end
end
