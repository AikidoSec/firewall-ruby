# frozen_string_literal: true

require "test_helper"

# ActionController::Live runs the action in a thread of its own, where the
# fiber-local context reads back as nil. Every scanner used to be skipped there,
# leaving streaming endpoints silently unprotected. These run against a real
# server, so the thread hop is the genuine one rather than the inline stub that
# rails/test_help installs.
# See https://github.com/AikidoSec/firewall-ruby/issues/357
class StreamingTest < ActiveSupport::TestCase
  include RailsServerHelpers
  include MockServerHelpers

  parallelize(workers: 1)

  ATTACK_PATH = "../../../../etc/passwd"

  test "a streaming action serves a legitimate request" do
    response = rails_get("/test/streaming?path=config/routes.rb")

    assert_equal "200", response.code
    assert_match(/data: \d+/, response.body)
  end

  test "a streaming action detects a path traversal attack" do
    response = rails_get("/test/streaming?path=#{ATTACK_PATH}")

    # Live commits the response before the action runs, so the attack surfaces
    # in the stream rather than as a 500.
    assert_equal "200", response.code
    assert_includes response.body, "Aikido::Zen::PathTraversalError"
  end

  test "a streaming action reports a detected_attack event" do
    # Settle first so our baseline is clean regardless of what ran before us.
    sleep 0.5

    baseline = received_events(type: "detected_attack").length

    rails_get("/test/streaming?path=#{ATTACK_PATH}")

    fresh = wait_for_event(type: "detected_attack", after_index: baseline, timeout: 5)

    assert_equal 1, fresh.length, "Expected exactly 1 detected_attack event, got #{fresh.length}"
    assert_equal "path_traversal", fresh.first.dig("attack", "kind")
  end
end
