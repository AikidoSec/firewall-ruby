# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RouteTest < ActiveSupport::TestCase
  test "two routes are equal if their verb and path are equal" do
    r1 = Aikido::Zen::Route.new(verb: "GET", path: "/")
    r2 = Aikido::Zen::Route.new(verb: "GET", path: "/")
    r3 = Aikido::Zen::Route.new(verb: "GET", path: "/nope")
    r4 = Aikido::Zen::Route.new(verb: "POST", path: "/")

    assert_equal r1, r2
    refute_equal r1, r3
    refute_equal r1, r4
  end

  test "routes can be used as hash keys" do
    r1 = Aikido::Zen::Route.new(verb: "GET", path: "/")
    r2 = Aikido::Zen::Route.new(verb: "GET", path: "/")

    counter = Hash.new(0)
    counter[r1] += 2

    assert_equal 2, counter[r2]
  end

  test "routes can be sorted by sort key" do
    routes = []
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_1")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_2")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_3")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_A")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_B")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_C")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_a")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_b")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login_c")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login1")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login2")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login3")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/loginA")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/loginB")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/loginC")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/logina")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/loginb")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/loginc")
    routes << Aikido::Zen::Route.new(verb: "DELETE", path: "/api/auth/login")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/login")
    routes << Aikido::Zen::Route.new(verb: "PATCH", path: "/api/auth/login")
    routes << Aikido::Zen::Route.new(verb: "POST", path: "/api/auth/login")
    routes << Aikido::Zen::Route.new(verb: "PUT", path: "/api/auth/login")
    routes << Aikido::Zen::Route.new(verb: "*", path: "/api/auth/login")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/")
    routes << Aikido::Zen::Route.new(verb: "*", path: "/")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/*/*/*/login_specific_method")
    routes << Aikido::Zen::Route.new(verb: "*", path: "/*/*/*/login_specific_method")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/*/auth/login")
    routes << Aikido::Zen::Route.new(verb: "*", path: "/*/auth/login")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/api/auth/*")
    routes << Aikido::Zen::Route.new(verb: "*", path: "/api/auth/*")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/*/auth/*")
    routes << Aikido::Zen::Route.new(verb: "*", path: "/*/auth/*")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "/*")
    routes << Aikido::Zen::Route.new(verb: "*", path: "/*")
    routes << Aikido::Zen::Route.new(verb: "GET", path: "*")
    routes << Aikido::Zen::Route.new(verb: "*", path: "*")

    assert_equal routes, routes.shuffle.sort_by(&:sort_key)
  end

  test "#as_json includes method and path" do
    route = Aikido::Zen::Route.new(verb: "GET", path: "/users/:id")
    assert_equal({method: "GET", path: "/users/:id"}, route.as_json)
  end

  test "routes support wildcard matching on verbs" do
    pattern = Aikido::Zen::Route.new(verb: "*", path: "/users")

    route1 = Aikido::Zen::Route.new(verb: "GET", path: "/users")
    route2 = Aikido::Zen::Route.new(verb: "POST", path: "/users")

    assert pattern.match?(route1)
    assert pattern.match?(route2)
  end

  test "routes support wildcard matching on paths" do
    pattern = Aikido::Zen::Route.new(verb: "GET", path: "/users/*")

    route1 = Aikido::Zen::Route.new(verb: "GET", path: "/users/1")
    route2 = Aikido::Zen::Route.new(verb: "GET", path: "/users/2")

    assert pattern.match?(route1)
    assert pattern.match?(route2)

    pattern = Aikido::Zen::Route.new(verb: "GET", path: "/users/*/file/*")

    route1 = Aikido::Zen::Route.new(verb: "GET", path: "/users/1/file/one.txt")
    route2 = Aikido::Zen::Route.new(verb: "GET", path: "/users/2/file/two.txt")

    assert pattern.match?(route1)
    assert pattern.match?(route2)
  end
end
