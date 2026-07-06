# frozen_string_literal: true

require "test_helper"

class WorkerProcessTest < ActiveSupport::TestCase
  include RailsServerHelpers
  include MockServerHelpers

  parallelize(workers: 1)

  # Mirrors config/puma.rb's worker count.
  WORKER_COUNT = Integer(ENV.fetch("WEB_CONCURRENCY", 2))

  test "worker process blocks a path traversal attack" do
    response = trigger_attack

    assert_equal "500", response.code

    body = JSON.parse(response.body)

    assert_not_nil body["error"]
  end

  test "worker process reports a detected_attack event for a path traversal attack" do
    # Settle first so our baseline is clean regardless of what ran before us
    # letting us assert an exact count below.
    sleep 0.5

    baseline = received_events(type: "detected_attack").length

    trigger_attack

    fresh = wait_for_event(type: "detected_attack", after_index: baseline, timeout: 5)

    assert_equal 1, fresh.length, "Expected exactly 1 detected_attack event, got #{fresh.length}"
    assert_equal "path_traversal", fresh.first.dig("attack", "kind")
  end

  test "each request from a worker produces a separate detected_attack event" do
    # Settle first so our baseline is clean regardless of what ran before us
    # letting us assert an exact count below.
    sleep 0.5

    baseline = received_events(type: "detected_attack").length

    count = 4

    count.times { trigger_attack }

    fresh = poll_until(timeout: 5) do
      events = received_events(type: "detected_attack")[baseline..]
      events if events.length >= count
    end

    assert_equal count, fresh.length, "Expected exactly #{count} detected_attack events, got #{fresh.length}"
  end

  test "worker IPC connection stays alive across keepalive intervals" do
    # Wait for at least one keepalive event.
    sleep 5

    responses_by_pid = poll_responses_by_pid(WORKER_COUNT, timeout: 5) { rails_get("/test/worker_process") }

    assert_equal WORKER_COUNT, responses_by_pid.size, "Expected requests to hit both worker processes"
  end

  test "worker processes receive updated settings from the parent via IPC" do
    configure_mock("blockedUserIds" => ["test-user"])

    responses_by_pid = poll_responses_by_pid(WORKER_COUNT, timeout: 10) do
      response = rails_get("/test/worker_process")
      response if JSON.parse(response.body)["blockedUserIds"] == ["test-user"]
    end

    assert_equal WORKER_COUNT, responses_by_pid.size, "Expected requests to hit both worker processes"
  end

  test "worker collector events are aggregated into the parent's heartbeat" do
    # Settle first so our baseline is clean regardless of what ran before us
    # letting us assert an exact count below.
    sleep 2

    baseline = received_events(type: "heartbeat").length

    attack_count = 0

    responses_by_pid = poll_responses_by_pid(WORKER_COUNT, timeout: 5) do
      attack_count += 1
      trigger_attack
    end

    assert_equal WORKER_COUNT, responses_by_pid.size, "Expected requests to hit both worker processes"

    heartbeats = poll_until(timeout: 10) do
      heartbeats = received_events(type: "heartbeat")[baseline..].map { |h| h.dig("stats", "requests", "attacksDetected") }
      heartbeats if heartbeats.sum { |a| a["total"].to_i } == attack_count
    end

    assert_equal attack_count, heartbeats.sum { |a| a["total"].to_i }
    assert_equal attack_count, heartbeats.sum { |a| a["blocked"].to_i }
  end

  test "worker process enforces rate limits delegated to the parent process" do
    configure_mock(
      "endpoints" => [{
        "method" => "GET",
        "route" => "/test/rate_limit(.:format)",
        "rateLimiting" => {
          "enabled" => true,
          "maxRequests" => 2,
          "windowSizeInMS" => 60_000
        }
      }]
    )

    # Wait for settings to propagate.
    sleep 2.5

    responses = 3.times.map { rails_get("/test/rate_limit") }
    assert_equal "200", responses[0].code
    assert_equal "200", responses[1].code
    assert_equal "429", responses[2].code
  end

  private

  def trigger_attack
    rails_get("/test/path_traversal?path=../../../../etc/passwd")
  end

  # Polls until a qualifying response has been seen from at least +count+
  # distinct worker PIDs (identified via the X-Worker-Pid response header),
  # accumulating the latest qualifying response per PID so that callers can
  # perform any further processing.
  #
  # @param count [Integer] number of distinct worker PIDs to wait for
  # @param timeout [Numeric] maximum seconds to wait before raising
  # @yieldreturn [Net::HTTPResponse, nil] the response if it qualifies,
  #   or nil if it does not qualify
  # @return [Hash] the latest qualifying response, keyed by worker PID
  # @raise [RuntimeError] if not seen from +count+ PIDs within +timeout+ seconds
  def poll_responses_by_pid(count, timeout: 5)
    responses_by_pid = {}

    poll_until(timeout: timeout) do
      response = yield
      next unless response

      responses_by_pid[response["X-Worker-Pid"]] = response
      responses_by_pid.size >= count
    end

    responses_by_pid
  end
end
