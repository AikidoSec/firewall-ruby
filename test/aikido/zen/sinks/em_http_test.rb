# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::EmHttpRequestTest < ActiveSupport::TestCase
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

  # Runs the block within the EM reactor loop. The block must return an EM::HTTP
  # object with request / response information.
  def within_reactor(&block)
    http = nil
    EventMachine.run do
      http = block.call
      http.callback { EventMachine.stop }
    end
    http
  end

  test "tracks HEAD requests made through .head" do
    assert_tracks_outbound_to "example.com", 443 do
      http = within_reactor { EventMachine::HttpRequest.new(@https_uri).head }
      assert_equal 200, http.response_header.status
    end

    assert_tracks_outbound_to "example.com", 80 do
      http = within_reactor { EventMachine::HttpRequest.new(@http_uri).head }
      assert_equal 200, http.response_header.status
    end

    assert_tracks_outbound_to "example.com", 8080 do
      http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).head }
      assert_equal 200, http.response_header.status
    end
  end

  test "tracks GET requests made through .get" do
    assert_tracks_outbound_to "example.com", 443 do
      http = within_reactor { EventMachine::HttpRequest.new(@https_uri).get }
      assert_equal "OK (443)", http.response
    end

    assert_tracks_outbound_to "example.com", 80 do
      http = within_reactor { EventMachine::HttpRequest.new(@http_uri).get }
      assert_equal "OK (80)", http.response
    end

    assert_tracks_outbound_to "example.com", 8080 do
      http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).get }
      assert_equal "OK (8080)", http.response
    end
  end

  test "tracks POST requests made through .post" do
    assert_tracks_outbound_to "example.com", 443 do
      http = within_reactor { EventMachine::HttpRequest.new(@https_uri).post(body: "test") }
      assert_equal "OK (443)", http.response
    end

    assert_tracks_outbound_to "example.com", 80 do
      http = within_reactor { EventMachine::HttpRequest.new(@http_uri).post(body: "test") }
      assert_equal "OK (80)", http.response
    end

    assert_tracks_outbound_to "example.com", 8080 do
      http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).post(body: "test") }
      assert_equal "OK (8080)", http.response
    end
  end

  test "tracks PUT requests made through .put" do
    assert_tracks_outbound_to "example.com", 443 do
      http = within_reactor { EventMachine::HttpRequest.new(@https_uri).put(body: "test") }
      assert_equal "OK (443)", http.response
    end

    assert_tracks_outbound_to "example.com", 80 do
      http = within_reactor { EventMachine::HttpRequest.new(@http_uri).put(body: "test") }
      assert_equal "OK (80)", http.response
    end

    assert_tracks_outbound_to "example.com", 8080 do
      http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).put(body: "test") }
      assert_equal "OK (8080)", http.response
    end
  end

  test "tracks PATCH requests made through .patch" do
    assert_tracks_outbound_to "example.com", 443 do
      http = within_reactor { EventMachine::HttpRequest.new(@https_uri).patch(body: "test") }
      assert_equal "OK (443)", http.response
    end

    assert_tracks_outbound_to "example.com", 80 do
      http = within_reactor { EventMachine::HttpRequest.new(@http_uri).patch(body: "test") }
      assert_equal "OK (80)", http.response
    end

    assert_tracks_outbound_to "example.com", 8080 do
      http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).patch(body: "test") }
      assert_equal "OK (8080)", http.response
    end
  end

  test "tracks DELETE requests made through .delete" do
    assert_tracks_outbound_to "example.com", 443 do
      http = within_reactor { EventMachine::HttpRequest.new(@https_uri).delete }
      assert_equal "OK (443)", http.response
    end

    assert_tracks_outbound_to "example.com", 80 do
      http = within_reactor { EventMachine::HttpRequest.new(@http_uri).delete }
      assert_equal "OK (80)", http.response
    end

    assert_tracks_outbound_to "example.com", 8080 do
      http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).delete }
      assert_equal "OK (8080)", http.response
    end
  end

  test "tracks OPTIONS requests made through .options" do
    assert_tracks_outbound_to "example.com", 443 do
      http = within_reactor { EventMachine::HttpRequest.new(@https_uri).options }
      assert_equal "OK (443)", http.response
    end

    assert_tracks_outbound_to "example.com", 80 do
      http = within_reactor { EventMachine::HttpRequest.new(@http_uri).options }
      assert_equal "OK (80)", http.response
    end

    assert_tracks_outbound_to "example.com", 8080 do
      http = within_reactor { EventMachine::HttpRequest.new(@custom_port_uri).options }
      assert_equal "OK (8080)", http.response
    end
  end
end
