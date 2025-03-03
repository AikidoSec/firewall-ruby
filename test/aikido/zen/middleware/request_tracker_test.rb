# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::RequestTrackerTest < ActiveSupport::TestCase
  setup do
    app = ->(env) { @downstream.call(env) }
    @middleware = Aikido::Zen::Middleware::RequestTracker.new(app)
    @downstream = ->(env) {
      status_code = env["PATH_INFO"].split("/").last.to_i
      [status_code, {}, ["OK"]]
    }
  end

  test "requests & routes get tracked in our stats funnel" do
    @middleware.call(Rack::MockRequest.env_for("/200"))
    @middleware.call(Rack::MockRequest.env_for("/200"))
    @middleware.call(Rack::MockRequest.env_for("/100"))
    @middleware.call(Rack::MockRequest.env_for("/200"))
    @middleware.call(Rack::MockRequest.env_for("/400"))

    # we made 5 request, 3 of them failing. We expect to have tracked:
    #  * 5 request
    #  * 1 route with 3 hits
    assert_equal Aikido::Zen.collector.stats.requests, 5
    assert_equal Aikido::Zen.collector.routes.visits.size, 1

    key = Aikido::Zen::Route.new(verb: "GET", path: "/:number")
    assert_equal Aikido::Zen.collector.routes.visits.keys, [key]
    assert_equal Aikido::Zen.collector.routes.visits[key].hits, 3
  end

  test "it rejects invalid status codes" do
    (100..199).each do |code|
      refute @middleware.track?(status_code: code, route: "/", http_method: "GET")
    end

    (400..599).each do |code|
      refute @middleware.track?(status_code: code, route: "/", http_method: "GET")
    end
  end

  test "it accepts valid status codes" do
    (200..399).each do |code|
      assert @middleware.track?(status_code: code, route: "/", http_method: "GET")
    end
  end

  test "it does not discover route for OPTIONS or HEAD methods" do
    refute @middleware.track?(status_code: 200, route: "/", http_method: "OPTIONS")
    refute @middleware.track?(status_code: 200, route: "/", http_method: "HEAD")
  end

  test "it does not discover route for OPTIONS or HEAD methods even with other status codes" do
    refute @middleware.track?(status_code: 404, route: "/", http_method: "OPTIONS")
    refute @middleware.track?(status_code: 405, route: "/", http_method: "HEAD")
  end

  test "it does not discover static files" do
    refute @middleware.track?(status_code: 200, route: "/service-worker.js", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/precache-manifest.10faec0bee24db502c8498078126dd53.js", http_method: "POST")
    refute @middleware.track?(status_code: 200, route: "/img/icons/favicon-16x16.png", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/fonts/icomoon.ttf", http_method: "GET")
  end

  test "it allows html files" do
    refute @middleware.track?(status_code: 200, route: "/index.html", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/contact.html", http_method: "GET")
  end

  test "it allows files with extension of one character" do
    assert @middleware.track?(status_code: 200, route: "/a.a", http_method: "GET")
  end

  test "it allows files with extension of 6 or more characters" do
    assert @middleware.track?(status_code: 200, route: "/a.aaaaaa", http_method: "GET")
    assert @middleware.track?(status_code: 200, route: "/a.aaaaaaa", http_method: "GET")
  end

  test 'it ignores files that end with ".properties"' do
    refute @middleware.track?(status_code: 200, route: "/file.properties", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/directory/file.properties", http_method: "GET")
  end

  test "it ignores files or directories that start with dot" do
    refute @middleware.track?(status_code: 200, route: "/.env", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/.aws/credentials", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/directory/.gitconfig", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/hello/.gitignore/file", http_method: "GET")
  end

  test "it ignores files that end with php (used as directory)" do
    refute @middleware.track?(status_code: 200, route: "/file.php", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/app_dev.php/_profiler/phpinfo", http_method: "GET")
  end

  test "it allows .well-known directory" do
    refute @middleware.track?(status_code: 200, route: "/.well-known", http_method: "GET")
    assert @middleware.track?(status_code: 200, route: "/.well-known/change-password", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/.well-known/security.txt", http_method: "GET")
  end

  test "it ignores certain strings" do
    refute @middleware.track?(status_code: 200, route: "/cgi-bin/luci/;stok=/locale", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/whatever/cgi-bin", http_method: "GET")
  end

  test "it should ignore fonts" do
    refute @middleware.track?(status_code: 200, route: "/fonts/icomoon.ttf", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/fonts/icomoon.woff", http_method: "GET")
    refute @middleware.track?(status_code: 200, route: "/fonts/icomoon.woff2", http_method: "GET")
  end

  test "it ignores files that end with .config" do
    refute @middleware.track?(status_code: 200, route: "/blog/App_Config/ConnectionStrings.config", http_method: "GET")
  end

  test "it allows redirects" do
    [301, 302, 303, 307, 308].each do |code|
      assert @middleware.track?(status_code: code, route: "/", http_method: "GET")
    end
  end

  test "it does not ignore normal routes" do
    assert @middleware.track?(status_code: 200, route: "/api/v1/users", http_method: "GET")
    assert @middleware.track?(status_code: 200, route: "/api/v1/users/1", http_method: "GET")
    assert @middleware.track?(status_code: 204, route: "/api/v1/users/1/friends", http_method: "POST")
  end
end
