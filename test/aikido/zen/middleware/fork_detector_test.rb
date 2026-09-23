# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::ForkDetectorTest < ActiveSupport::TestCase
  setup do
    @downstream_calls = []
    app = ->(env) { @downstream_calls << env }
    @middleware = Aikido::Zen::Middleware::ForkDetector.new(app)
  end

  test "does not call Zen.fork! when the process id has not changed" do
    Aikido::Zen.stub :fork!, -> { flunk "should not have forked" } do
      @middleware.call({})
      @middleware.call({})
    end

    assert_equal 2, @downstream_calls.size
  end

  test "calls Zen.fork! exactly once when the process id changes, then calls the app" do
    fork_calls = 0

    Aikido::Zen.stub :fork!, -> { fork_calls += 1 } do
      Process.stub :pid, 12345 do
        @middleware.call({})
        @middleware.call({})
      end
    end

    assert_equal 1, fork_calls
    assert_equal 2, @downstream_calls.size
  end

  test "a request that races in while another thread is still forking waits, then does not fork again" do
    fork_calls = 0
    fork_started = Queue.new
    release_fork = Queue.new

    slow_fork = -> {
      fork_calls += 1
      fork_started << true
      release_fork.pop
    }

    Aikido::Zen.stub :fork!, slow_fork do
      Process.stub :pid, 12345 do
        forking_thread = Thread.new { @middleware.call({}) }

        fork_started.pop

        racing_thread = Thread.new { @middleware.call({}) }

        # Give the racing thread a chance to reach the mutex before we let the
        # fork finish, so it genuinely blocks rather than running afterwards.
        sleep 0.05

        release_fork << true

        forking_thread.join(2)
        racing_thread.join(2)
      end
    end

    assert_equal 1, fork_calls
    assert_equal 2, @downstream_calls.size
  end
end
