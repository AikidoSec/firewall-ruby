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
