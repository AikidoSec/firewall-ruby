# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::SetCurrentRequestTest < ActiveSupport::TestCase
  setup do
    @requests = []
    app = ->(env) { @downstream.call(env) }
    @middleware = Aikido::Agent::SetCurrentRequest.new(app)
    @downstream = ->(env) { @requests << env }
  end

  test "makes Agent.current_request available in the downstream app but not outside" do
    @downstream = ->(env) do
      refute_nil Aikido::Agent.current_request
      assert_kind_of Aikido::Agent::Request, Aikido::Agent.current_request
      @requests << Aikido::Agent.current_request
      [200, {}, []]
    end

    result = @middleware.call({"PATH_INFO" => "/"})

    assert_equal [200, {}, []], result
    assert_nil Aikido::Agent.current_request
  end

  test "separate threads get access to a different request object" do
    requests = {}

    @downstream = ->(env) do
      requests[Thread.current.object_id] = Aikido::Agent.current_request
    end

    t1 = Thread.new { @middleware.call({"PATH_INFO" => "/foo"}) }
    t2 = Thread.new { @middleware.call({"PATH_INFO" => "/bar"}) }

    t1.join
    t2.join

    assert_equal "/foo", requests[t1.object_id].path
    assert_equal "/bar", requests[t2.object_id].path
  end

  test "requests get tracked in our stats funnel" do
    runner = Aikido::Agent.send(:runner)

    assert_changes -> { runner.stats.requests }, from: 0, to: 3 do
      @middleware.call({"PATH_INFO" => "/"})
      @middleware.call({"PATH_INFO" => "/"})
      @middleware.call({"PATH_INFO" => "/"})
    end
  end
end
