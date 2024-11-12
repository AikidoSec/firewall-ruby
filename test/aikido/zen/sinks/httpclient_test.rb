# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Sinks::HTTPClientTest < ActiveSupport::TestCase
  class SSRFDetectionTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include SinkAttackHelpers

    setup do
      stub_request(:get, "https://localhost/safe")
        .to_return(status: 200, body: "OK")
    end

    test "allows normal requests" do
      refute_attack do
        response = HTTPClient.get("https://localhost/safe")
        assert_equal "OK", response.body
      end

      assert_requested :get, "https://localhost/safe"
    end

    test "prevents requests to hosts that come from user input" do
      set_context_from_request_to "/?host=localhost"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        HTTPClient.get("https://localhost/safe")
      end

      assert_not_requested :get, "https://localhost/safe"
    end

    test "does not fail if a context is not set" do
      Aikido::Zen.current_context = nil

      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "")

      refute_attack do
        HTTPClient.get("http://localhost")
      end

      assert_requested :get, "http://localhost"
    end

    test "raises a useful error message" do
      set_context_from_request_to "/?host=localhost"

      error = assert_attack Aikido::Zen::Attacks::SSRFAttack do
        HTTPClient.get("https://localhost/safe")
      end

      assert_equal \
        "SSRF: Request to user-supplied hostname «localhost» detected in httpclient.request (GET https://localhost/safe).",
        error.message
    end

    test "does not log an outbound connection if the request was blocked" do
      set_context_from_request_to "/?host=localhost"

      assert_no_difference "Aikido::Zen.collector.hosts.size" do
        assert_attack Aikido::Zen::Attacks::SSRFAttack do
          HTTPClient.get("https://localhost/safe")
        end
      end
    end

    test "prevents requests to redirected domains when the origin is user input" do
      skip <<~REASON.tr("\n", " ")
        The way that webmock patches httpclient hacks the response building such
        that we cannot intercept it to track the redirection in the tests.
        For now, this has been tested manually to work. We need to figure out
        how to improve this test.
      REASON

      stub_request(:get, "http://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        response = HTTPClient.get("http://this-is-harmless-i-swear.com/")
        assert_equal 301, response.status

        HTTPClient.get(response.headers["Location"])
      end

      assert_requested :get, "http://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
    end

    test "prevents automated requests to redirected domains when the origin is user input" do
      skip <<~REASON.tr("\n", " ")
        The way that webmock patches httpclient hacks the response building such
        that we cannot intercept it to track the redirection in the tests.
        For now, this has been tested manually to work. We need to figure out
        how to improve this test.
      REASON

      stub_request(:get, "http://this-is-harmless-i-swear.com/")
        .to_return(status: 301, headers: {"Location" => "http://localhost/"})
      stub_request(:get, "http://localhost/")
        .to_return(status: 200, body: "you've been pwnd")

      set_context_from_request_to "/?host=this-is-harmless-i-swear.com"

      assert_attack Aikido::Zen::Attacks::SSRFAttack do
        HTTPClient.get("http://this-is-harmless-i-swear.com/", follow_redirect: true)
      end

      assert_requested :get, "http://this-is-harmless-i-swear.com"
      assert_not_requested :get, "http://localhost"
    end
  end

  class ConnectionTrackingTest < ActiveSupport::TestCase
    include StubsCurrentContext
    include HTTPConnectionTrackingAssertions

    setup do
      @http_uri = URI("http://example.com/path")
      @https_uri = URI("https://example.com/path")
      @custom_port_uri = URI("http://example.com:8080/path")

      stub_request(:any, @http_uri).to_return(status: 200, body: "OK (80)")
      stub_request(:any, @https_uri).to_return(status: 200, body: "OK (443)")
      stub_request(:any, @custom_port_uri).to_return(status: 200, body: "OK (8080)")
    end

    class ClassMethodsTest < self
      test "tracks HEAD requests made through .head" do
        assert_tracks_outbound_to "example.com", 443 do
          response = HTTPClient.head(@https_uri)
          assert_equal 200, response.status
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = HTTPClient.head(@http_uri)
          assert_equal 200, response.status
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = HTTPClient.head(@custom_port_uri)
          assert_equal 200, response.status
        end
      end

      test "tracks GET requests made through .get" do
        assert_tracks_outbound_to "example.com", 443 do
          response = HTTPClient.get(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = HTTPClient.get(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = HTTPClient.get(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks GET requests made through .get_content" do
        assert_tracks_outbound_to "example.com", 443 do
          assert_equal "OK (443)", HTTPClient.get_content(@https_uri)
        end

        assert_tracks_outbound_to "example.com", 80 do
          assert_equal "OK (80)", HTTPClient.get_content(@http_uri)
        end

        assert_tracks_outbound_to "example.com", 8080 do
          assert_equal "OK (8080)", HTTPClient.get_content(@custom_port_uri)
        end
      end

      test "tracks POST requests made through .post" do
        assert_tracks_outbound_to "example.com", 443 do
          response = HTTPClient.post(@https_uri, body: "data")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = HTTPClient.post(@http_uri, body: "data")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = HTTPClient.post(@custom_port_uri, body: "data")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks POST requests made through .post_content" do
        assert_tracks_outbound_to "example.com", 443 do
          assert_equal "OK (443)", HTTPClient.post_content(@https_uri, body: {"form" => "field"})
        end

        assert_tracks_outbound_to "example.com", 80 do
          assert_equal "OK (80)", HTTPClient.post_content(@http_uri, body: {"form" => "field"})
        end

        assert_tracks_outbound_to "example.com", 8080 do
          assert_equal "OK (8080)", HTTPClient.post_content(@custom_port_uri, body: {"form" => "field"})
        end
      end

      test "tracks PUT requests made through .put" do
        assert_tracks_outbound_to "example.com", 443 do
          response = HTTPClient.put(@https_uri, body: "data")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = HTTPClient.put(@http_uri, body: "data")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = HTTPClient.put(@custom_port_uri, body: "data")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks DELETE requests made through .delete" do
        assert_tracks_outbound_to "example.com", 443 do
          response = HTTPClient.delete(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = HTTPClient.delete(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = HTTPClient.delete(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks OPTIONS requests made through .options" do
        assert_tracks_outbound_to "example.com", 443 do
          response = HTTPClient.options(@https_uri, body: "data")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = HTTPClient.options(@http_uri, body: "data")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = HTTPClient.options(@custom_port_uri, body: "data")
          assert_equal "OK (8080)", response.body
        end
      end
    end

    class ClientInstanceTest < self
      setup { @client = HTTPClient.new }

      test "tracks HEAD requests made through #head" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.head(@https_uri)
          assert_equal 200, response.status
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.head(@http_uri)
          assert_equal 200, response.status
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.head(@custom_port_uri)
          assert_equal 200, response.status
        end
      end

      test "tracks GET requests made through #get" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.get(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.get(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.get(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks GET requests made through #get_content" do
        assert_tracks_outbound_to "example.com", 443 do
          assert_equal "OK (443)", @client.get_content(@https_uri)
        end

        assert_tracks_outbound_to "example.com", 80 do
          assert_equal "OK (80)", @client.get_content(@http_uri)
        end

        assert_tracks_outbound_to "example.com", 8080 do
          assert_equal "OK (8080)", @client.get_content(@custom_port_uri)
        end
      end

      test "tracks POST requests made through #post" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.post(@https_uri, body: "data")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.post(@http_uri, body: "data")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.post(@custom_port_uri, body: "data")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks POST requests made through #post_content" do
        assert_tracks_outbound_to "example.com", 443 do
          assert_equal "OK (443)", @client.post_content(@https_uri, body: {"form" => "field"})
        end

        assert_tracks_outbound_to "example.com", 80 do
          assert_equal "OK (80)", @client.post_content(@http_uri, body: {"form" => "field"})
        end

        assert_tracks_outbound_to "example.com", 8080 do
          assert_equal "OK (8080)", @client.post_content(@custom_port_uri, body: {"form" => "field"})
        end
      end

      test "tracks PUT requests made through #put" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.put(@https_uri, body: "data")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.put(@http_uri, body: "data")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.put(@custom_port_uri, body: "data")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks PATCH requests made through #patch" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.patch(@https_uri, body: "data")
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.patch(@http_uri, body: "data")
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.patch(@custom_port_uri, body: "data")
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks DELETE requests made through #delete" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.delete(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.delete(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.delete(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks OPTIONS requests made through #options" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.options(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.options(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.options(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end

      test "tracks TRACE requests made through #trace" do
        assert_tracks_outbound_to "example.com", 443 do
          response = @client.trace(@https_uri)
          assert_equal "OK (443)", response.body
        end

        assert_tracks_outbound_to "example.com", 80 do
          response = @client.trace(@http_uri)
          assert_equal "OK (80)", response.body
        end

        assert_tracks_outbound_to "example.com", 8080 do
          response = @client.trace(@custom_port_uri)
          assert_equal "OK (8080)", response.body
        end
      end
    end

    class AsyncMethodsTest < self
      setup { @client = HTTPClient.new }

      test "tracks HEAD requests made through #head_async" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.head_async(@https_uri)
          response = connection.pop
          assert_equal 200, response.status
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.head_async(@http_uri)
          response = connection.pop
          assert_equal 200, response.status
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.head_async(@custom_port_uri)
          response = connection.pop
          assert_equal 200, response.status
        end
      end

      test "tracks GET requests made through #get" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.get_async(@https_uri)
          response = connection.pop
          assert_equal "OK (443)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.get_async(@http_uri)
          response = connection.pop
          assert_equal "OK (80)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.get_async(@custom_port_uri)
          response = connection.pop
          assert_equal "OK (8080)", response.body.read
        end
      end

      test "tracks POST requests made through #post" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.post_async(@https_uri, body: "data")
          response = connection.pop
          assert_equal "OK (443)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.post_async(@http_uri, body: "data")
          response = connection.pop
          assert_equal "OK (80)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.post_async(@custom_port_uri, body: "data")
          response = connection.pop
          assert_equal "OK (8080)", response.body.read
        end
      end

      test "tracks PUT requests made through #put" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.put_async(@https_uri, body: "data")
          response = connection.pop
          assert_equal "OK (443)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.put_async(@http_uri, body: "data")
          response = connection.pop
          assert_equal "OK (80)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.put_async(@custom_port_uri, body: "data")
          response = connection.pop
          assert_equal "OK (8080)", response.body.read
        end
      end

      test "tracks PATCH requests made through #patch" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.patch_async(@https_uri, body: "data")
          response = connection.pop
          assert_equal "OK (443)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.patch_async(@http_uri, body: "data")
          response = connection.pop
          assert_equal "OK (80)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.patch_async(@custom_port_uri, body: "data")
          response = connection.pop
          assert_equal "OK (8080)", response.body.read
        end
      end

      test "tracks DELETE requests made through #delete" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.delete_async(@https_uri)
          response = connection.pop
          assert_equal "OK (443)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.delete_async(@http_uri)
          response = connection.pop
          assert_equal "OK (80)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.delete_async(@custom_port_uri)
          response = connection.pop
          assert_equal "OK (8080)", response.body.read
        end
      end

      test "tracks OPTIONS requests made through #options" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.options_async(@https_uri)
          response = connection.pop
          assert_equal "OK (443)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.options_async(@http_uri)
          response = connection.pop
          assert_equal "OK (80)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.options_async(@custom_port_uri)
          response = connection.pop
          assert_equal "OK (8080)", response.body.read
        end
      end

      test "tracks TRACE requests made through #trace" do
        assert_tracks_outbound_to "example.com", 443 do
          connection = @client.trace_async(@https_uri)
          response = connection.pop
          assert_equal "OK (443)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 80 do
          connection = @client.trace_async(@http_uri)
          response = connection.pop
          assert_equal "OK (80)", response.body.read
        end

        assert_tracks_outbound_to "example.com", 8080 do
          connection = @client.trace_async(@custom_port_uri)
          response = connection.pop
          assert_equal "OK (8080)", response.body.read
        end
      end
    end
  end
end
