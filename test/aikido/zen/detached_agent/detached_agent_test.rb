# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::DetachedAgent::AgentTest < ActiveSupport::TestCase
  include WorkerHelpers

  def with_mocks(front_object, on_drb_start)
    DRbObject.stub :new_with_uri, front_object do
      DRb.stub :start_service, on_drb_start do
        config = Aikido::Zen.config
        collector = Minitest::Mock.new
        worker = MockWorker.new
        interval = 10

        detached_agent_agent = Aikido::Zen::DetachedAgent::Agent.new(
          heartbeat_interval: interval,
          config: config,
          worker: worker,
          collector: collector
        )

        yield ({
          agent: detached_agent_agent,
          interval: interval,
          config: config,
          worker: worker,
          collector: collector
        })
      end
    end
  end

  test "child to parent heartbeats are scheduled" do
    drb_start_called = false
    on_drb_start = -> { drb_start_called = true }

    with_mocks(Minitest::Mock.new, on_drb_start) do |mocks|
      assert_equal 1, mocks[:worker].jobs.size
      timer = mocks[:worker].jobs.first
      assert_equal mocks[:interval], timer.execution_interval
    end

    refute drb_start_called
  end

  test "heartbeats are send to the front object" do
    drb_start_called = false
    on_drb_start = -> { drb_start_called = true }
    front_object = Minitest::Mock.new

    with_mocks(front_object, on_drb_start) do |mocks|
      at = Time.now
      hb = {dummy: :heartbeat}

      front_object.expect(:send_heartbeat_to_parent_process, nil, [{"dummy" => "heartbeat"}])

      stats = Minitest::Mock.new
      stats.expect :any?, true

      mocks[:collector].expect(:stats, stats)
      mocks[:collector].expect(:flush, hb, [], at: at)

      mocks[:agent].send_heartbeat(at: at)

      assert_mock stats
      assert_mock mocks[:collector]
    end

    assert_mock front_object
    refute drb_start_called
  end

  test "forks are properly handled" do
    drb_start_called = false
    on_drb_start = -> { drb_start_called = true }

    with_mocks(Minitest::Mock.new, on_drb_start) do |mocks|
      mocks[:agent].handle_fork

      assert mocks[:worker].shutdown_called
      refute_same mocks[:worker], mocks[:agent].worker
      assert drb_start_called
    end
  end
end
