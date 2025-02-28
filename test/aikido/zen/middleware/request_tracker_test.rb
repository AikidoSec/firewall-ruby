# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::Middleware::RequestTrackerTest < ActiveSupport::TestCase
  setup do
    @contexts = []
    app = ->(env) { @downstream.call(env) }
    @middleware = Aikido::Zen::Middleware::RequestTracker.new(app)
    @downstream = ->(env) { @contexts << env }
  end

  test "requests get tracked in our stats funnel" do
    assert_difference "Aikido::Zen.collector.stats.requests", +3 do
      @middleware.call(Rack::MockRequest.env_for("/"))
      @middleware.call(Rack::MockRequest.env_for("/"))
      @middleware.call(Rack::MockRequest.env_for("/"))
    end
  end
end
