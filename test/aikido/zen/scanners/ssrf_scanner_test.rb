# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Scanners::SSRFScannerTest < ActiveSupport::TestCase
  setup { @redirects = Aikido::Zen::Scanners::SSRFScanner::RedirectChains.new }

  def assert_attack(request_uri, input, reason = "`#{input}` was not blocked")
    scanner = Aikido::Zen::Scanners::SSRFScanner.new(URI(request_uri), input, @redirects)
    assert scanner.attack?, reason
  end

  def refute_attack(request_uri, input, reason = "`#{input}` was blocked")
    scanner = Aikido::Zen::Scanners::SSRFScanner.new(URI(request_uri), input, @redirects)
    refute scanner.attack?, reason
  end

  test "allows the request when either the hostname or input are empty" do
    refute_attack "", ""
    refute_attack "http://example.com", ""
    refute_attack "", "example.com"
  end

  test "allows user input in the path" do
    refute_attack "http://example.com/localhost", "localhost"
  end

  test "allows user input that is bigger than the hostname" do
    refute_attack "http://localhost", "localhost localhost"
  end

  test "allows requests to hosts that don't resolve to internal IPs" do
    refute_attack "http://google.com/search?q=test", "google.com"
  end

  test "it ignores URIs that can't be parsed correctly" do
    # URI.parse will either fail or return URIs without a "hostname" for these,
    # so HTTP libs will fail to make a request, so we can ignore these cases.
    refute_attack "http:/localhost", "localhost"
    refute_attack "http:localhost", "localhost"
    refute_attack "localhost", "localhost"
    refute_attack "http://", "localhost"
  end

  test "detects when the input is the request hostname" do
    assert_attack "http://localhost/", "localhost"
    assert_attack "https://localhost/", "localhost"
  end

  test "detects when the input is in the request hostname regardless of path" do
    assert_attack "http://localhost/path", "localhost"
    assert_attack "https://localhost/path", "localhost"
  end

  test "it detects the input in URIs with a different protocol" do
    assert_attack "ftp://localhost", "localhost"
  end

  test "it detects IP addresses in user input" do
    assert_attack "http://169.254.169.254/latest/meta-data/", "169.254.169.254"
    assert_attack "http://[::1]/", "::1"
    assert_attack "http://[::1]/", "[::1]"
    assert_attack "http://[fe80::3e8]", "fe80::3e8"
    assert_attack "http://[fe80::3e8]", "[fe80::3e8]"
  end

  test "it allows inputs with a port that does not match the connection" do
    refute_attack "http://localhost/", "localhost:8080"
    refute_attack "http://localhost:8080", "localhost"
  end

  test "it detects inputs with ports only if they match the connection's port" do
    assert_attack "http://localhost/", "localhost:80"
    assert_attack "https://localhost/", "localhost:443"
    assert_attack "https://localhost:8080/", "localhost:8080"
  end

  test "it allows connections if the input has a port but that's not used" do
    refute_attack "http://localhost/", "localhost:8080"
    refute_attack "http://[::1]/", "[::1]:8080"
  end

  test "it checks the input against the origin of any matching redirect chain" do
    @redirects
      .add(source: URI("https://harmless.com/foo"), destination: URI("https://harmless.com/bar"))
      .add(source: URI("https://harmless.com/bar"), destination: URI("http://localhost/bar"))

    assert_attack "http://localhost/bar", "harmless.com"
  end

  module HeaderNormalizationTests
    extend ActiveSupport::Testing::Declarative

    test "it normalizes header keys to be downcase" do
      wrapper = build_wrapper(headers: {"Content-Length" => "1", "CONTENT-TYPE" => "text/html"})

      assert_equal ["content-length", "content-type"], wrapper.headers.keys
    end

    test "it defaults to normalizing values to strings" do
      wrapper = build_wrapper(headers: {"Content-Length" => 1})

      assert_equal "1", wrapper.headers["content-length"]
    end

    test "it can receive a proc to normalize the value" do
      wrapper = build_wrapper(
        headers: {"Content-Length" => "1234"},
        header_normalizer: ->(value) { value.reverse }
      )

      assert_equal "4321", wrapper.headers["content-length"]
    end

    test "it only normalizes the headers once" do
      counter = 0
      normalizer = ->(value) {
        counter += 1
        value
      }

      wrapper = build_wrapper(
        headers: {"Content-Length" => "100"},
        header_normalizer: normalizer
      )

      assert_difference "counter", +1 do
        wrapper.headers
        wrapper.headers
      end
    end
  end

  class RequestWrapperTest < ActiveSupport::TestCase
    include HeaderNormalizationTests

    def build_wrapper(verb: "GET", uri: URI("https://example.com"), headers: {}, **opts)
      Aikido::Zen::Scanners::SSRFScanner::Request.new(
        verb: verb, uri: uri, headers: headers, **opts
      )
    end

    test "it enforces the URI being a URI" do
      req = build_wrapper(uri: "http://example.com/path")
      assert_kind_of URI, req.uri
      assert_equal "http://example.com/path", req.uri.to_s
    end

    test "it enforces the verb is in uppercase" do
      req = build_wrapper(verb: :get)
      assert_equal "GET", req.verb
    end

    test "#to_s includes the verb and URI" do
      req = build_wrapper(verb: :post, uri: "https://example.com/path")
      assert_equal "POST https://example.com/path", req.to_s
    end

    test "#to_s behaves well if the verb is empty (see Curb's sink)" do
      req = build_wrapper(verb: nil, uri: "https://example.com/path")
      assert_equal "https://example.com/path", req.to_s
    end
  end

  class ResponseWrapperTest < ActiveSupport::TestCase
    include HeaderNormalizationTests

    def build_wrapper(status: "200", headers: {}, **opts)
      Aikido::Zen::Scanners::SSRFScanner::Response.new(
        status: status, headers: headers, **opts
      )
    end

    test "it enforces the status code is a string" do
      resp = build_wrapper(status: 200)
      assert_equal "200", resp.status
    end

    test "it expects a 3XX status to consider itself a redirect" do
      ok_resp = build_wrapper(status: 200, headers: {"Location" => "/"})
      refute ok_resp.redirect?

      moved_resp = build_wrapper(status: 301, headers: {"Location" => "/"})
      assert moved_resp.redirect?
    end

    test "it does not consider it a redirect if there's no Location header" do
      resp = build_wrapper(status: 301, headers: {})
      refute resp.redirect?
    end

    test "it knows the redirect URI (and makes sure it's a URI)" do
      resp = build_wrapper(status: 301, headers: {"Location" => "/"})
      assert_equal URI("/"), resp.redirect_to
    end

    test "the redirect URI is nil if the status is not 3XX" do
      resp = build_wrapper(status: 200, headers: {"Location" => "/"})
      assert_nil resp.redirect_to
    end

    test "it does not check the headers unless the status is 3XX" do
      resp = build_wrapper(status: 200, headers: {})
      assert_nil resp.redirect_to

      # This is to avoid normalizing the headers unless we absolutely need to
      refute resp.instance_variable_get(:@normalized_headers)
    end
  end

  class RedirectChainTest < ActiveSupport::TestCase
    setup { @redirects = Aikido::Zen::Scanners::SSRFScanner::RedirectChains.new }

    test "#origin returns nil for an empty chain" do
      uri = URI("http://example.com")
      assert_nil @redirects.origin(uri)
    end

    test "#origin returns the correct value when there was a single redirect" do
      source = URI("https://example.com")
      dest = URI("https://hackers.com")

      @redirects.add(source: source, destination: dest)

      assert_equal source, @redirects.origin(dest)
    end

    test "#origin tracks the correct value for a longer chain" do
      links = [
        URI("https://example.com"),
        URI("https://intermediary.com"),
        URI("https://other.com"),
        URI("https://hackers.com")
      ]

      links.each_cons(2) { |from, to| @redirects.add(source: from, destination: to) }

      assert_equal links.first, @redirects.origin(links[1])
      assert_equal links.first, @redirects.origin(links[2])
      assert_equal links.first, @redirects.origin(links[3])
    end

    test "#origin tracks the correct value for a chain with same-host redirects" do
      links = [
        URI("https://example.com/one"),
        URI("https://example.com/two"),
        URI("https://hackers.com")
      ]

      links.each_cons(2) { |from, to| @redirects.add(source: from, destination: to) }

      assert_equal links.first, @redirects.origin(links[1])
      assert_equal links.first, @redirects.origin(links[2])
    end

    test "multiple chains can be tracked simultaneously" do
      chain_1 = [
        URI("https://example.com/one"),
        URI("https://example.com/two"),
        URI("https://hackers.com")
      ]
      chain_2 = [
        URI("https://example.com/three"),
        URI("https://itsfine.com")
      ]

      chain_1.each_cons(2) { |from, to| @redirects.add(source: from, destination: to) }
      chain_2.each_cons(2) { |from, to| @redirects.add(source: from, destination: to) }

      assert_equal chain_1.first, @redirects.origin(chain_1.last)
      assert_equal chain_2.first, @redirects.origin(chain_2.last)
    end

    test "avoids an infinite loop if you have circular redirects" do
      link_1 = URI("https://example.com/1")
      link_2 = URI("https://example.com/2")

      @redirects.add(source: link_1, destination: link_2)
      @redirects.add(source: link_2, destination: link_1)

      assert_equal link_1, @redirects.origin(link_2)
      assert_equal link_2, @redirects.origin(link_1)
    end

    test "cyclic redirects after the start of a chain are resolved" do
      root = URI("https://example.com/root")
      link_1 = URI("https://example.com/1")
      link_2 = URI("https://example.com/2")

      @redirects.add(source: root, destination: link_1)
      @redirects.add(source: link_1, destination: link_2)
      @redirects.add(source: link_2, destination: link_1)

      assert_equal root, @redirects.origin(link_1)
    end
  end
end
