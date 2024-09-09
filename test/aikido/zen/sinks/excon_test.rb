# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::ExconTest < ActiveSupport::TestCase
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

  class ClassMethodsTest < self
    test "tracks GET requests made through .get" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.get(@https_uri.to_s)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.get(@http_uri.to_s)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.get(@custom_port_uri.to_s)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks POST requests made through .post" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.post(@https_uri.to_s, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.post(@http_uri.to_s, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.post(@custom_port_uri.to_s, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PUT requests made through .put" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.put(@https_uri.to_s, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.put(@http_uri.to_s, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.put(@custom_port_uri.to_s, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PATCH requests made through .patch" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.patch(@https_uri.to_s, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.patch(@http_uri.to_s, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.patch(@custom_port_uri.to_s, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks DELETE requests made through .delete" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.delete(@https_uri.to_s)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.delete(@http_uri.to_s)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.delete(@custom_port_uri.to_s)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks OPTIONS requests made through .options" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.options(@https_uri.to_s)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.options(@http_uri.to_s)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.options(@custom_port_uri.to_s)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks TRACE requests made through .trace" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.trace(@https_uri.to_s)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.trace(@http_uri.to_s)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.trace(@custom_port_uri.to_s)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks CONNECT requests made through .connect" do
      assert_tracks_outbound_to "example.com", 443 do
        response = Excon.connect(@https_uri.to_s)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        response = Excon.connect(@http_uri.to_s)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        response = Excon.connect(@custom_port_uri.to_s)
        assert_equal "OK (8080)", response.body
      end
    end
  end

  class InstanceMethodsTest < self
    test "tracks GET requests made through #get" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.get
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.get
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.get
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks POST requests made through #post" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.post(body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.post(body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.post(body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PUT requests made through #put" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.put(body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.put(body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.put(body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PATCH requests made through #patch" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.patch(body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.patch(body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.patch(body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks DELETE requests made through #delete" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.delete
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.delete
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.delete
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks OPTIONS requests made through #options" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.options
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.options
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.options
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks TRACE requests made through #trace" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.trace
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.trace
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.trace
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks CONNECT requests made through #connect" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.to_s)
        response = client.connect
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.to_s)
        response = client.connect
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.to_s)
        response = client.connect
        assert_equal "OK (8080)", response.body
      end
    end
  end

  class PassingOptionsTest < self
    test "tracks GET requests made through .get" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.get(path: @https_uri.path)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.get(path: @http_uri.path)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.get(path: @custom_port_uri.path)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks POST requests made through .post" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.post(path: @https_uri.path, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.post(path: @http_uri.path, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.post(path: @custom_port_uri.path, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PUT requests made through .put" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.put(path: @https_uri.path, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.put(path: @http_uri.path, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.put(path: @custom_port_uri.path, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks PATCH requests made through .patch" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.patch(path: @https_uri.path, body: "test")
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.patch(path: @http_uri.path, body: "test")
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.patch(path: @custom_port_uri.path, body: "test")
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks DELETE requests made through .delete" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.delete(path: @https_uri.path)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.delete(path: @http_uri.path)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.delete(path: @custom_port_uri.path)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks OPTIONS requests made through .options" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.options(path: @https_uri.path)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.options(path: @http_uri.path)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.options(path: @custom_port_uri.path)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks TRACE requests made through .trace" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.trace(path: @https_uri.path)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.trace(path: @http_uri.path)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.trace(path: @custom_port_uri.path)
        assert_equal "OK (8080)", response.body
      end
    end

    test "tracks CONNECT requests made through .connect" do
      assert_tracks_outbound_to "example.com", 443 do
        client = Excon.new(@https_uri.origin)
        response = client.connect(path: @https_uri.path)
        assert_equal "OK (443)", response.body
      end

      assert_tracks_outbound_to "example.com", 80 do
        client = Excon.new(@http_uri.origin)
        response = client.connect(path: @http_uri.path)
        assert_equal "OK (80)", response.body
      end

      assert_tracks_outbound_to "example.com", 8080 do
        client = Excon.new(@custom_port_uri.origin)
        response = client.connect(path: @custom_port_uri.path)
        assert_equal "OK (8080)", response.body
      end
    end
  end
end
