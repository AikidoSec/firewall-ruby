# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::PayloadTest < ActiveSupport::TestCase
  test "query payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :query, "path")
    assert_equal({payload: "value", source: "query", pathToPayload: "path"}, payload.as_json)
  end

  test "body payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :body, "path")
    assert_equal({payload: "value", source: "body", pathToPayload: "path"}, payload.as_json)
  end

  test "header payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :header, "path")
    assert_equal({payload: "value", source: "headers", pathToPayload: "path"}, payload.as_json)
  end

  test "cookie payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :cookie, "path")
    assert_equal({payload: "value", source: "cookies", pathToPayload: "path"}, payload.as_json)
  end

  test "route payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :route, "path")
    assert_equal({payload: "value", source: "routeParams", pathToPayload: "path"}, payload.as_json)
  end

  test "graphql payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :graphql, "path")
    assert_equal({payload: "value", source: "graphql", pathToPayload: "path"}, payload.as_json)
  end

  test "xml payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :xml, "path")
    assert_equal({payload: "value", source: "xml", pathToPayload: "path"}, payload.as_json)
  end

  test "subdomain payloads have the proper JSON serialization" do
    payload = Aikido::Zen::Payload.new("value", :subdomain, "path")
    assert_equal({payload: "value", source: "subdomains", pathToPayload: "path"}, payload.as_json)
  end
end
