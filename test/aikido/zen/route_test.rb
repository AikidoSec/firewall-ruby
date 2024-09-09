# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::RouteTest < ActiveSupport::TestCase
  test "two routes are equal if their verb and path are equql" do
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
end
