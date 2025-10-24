# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::DetachedAgent::FrontObjectTest < ActiveSupport::TestCase
  setup do
    @config = Aikido::Zen::Config.new
    @collector = Aikido::Zen::Collector.new(config: @config)
    @front_object = Aikido::Zen::DetachedAgent::FrontObject.new(config: @config, collector: @collector)
  end

  test "it pushes collector events into collector" do
    input_events = Array.new(3) { Aikido::Zen::Collector::Events::TrackRequest.new }
    input_events_data = input_events.map(&:as_json)

    @front_object.send_collector_events(input_events_data)

    output_events = @collector.flush_events

    assert_equal output_events.map(&:as_json), input_events_data
  end
end
