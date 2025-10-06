# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::IPC::FrontObjectTest < ActiveSupport::TestCase
  setup do
    @config = Aikido::Zen::Config.new
    @collector = Minitest::Mock.new(Aikido::Zen::Collector.new(config: @config))
    @front_object = Aikido::Zen::IPC::FrontObject.new(config: @config, collector: @collector)
  end

  test "it pushes heartbeats into collector" do
    hb = {dummy: :heartbeat}
    @front_object.send_heartbeat_to_parent_process(hb)
    @front_object.send_heartbeat_to_parent_process(hb)
    @front_object.send_heartbeat_to_parent_process(hb)

    heartbeats = @collector.flush_heartbeats

    assert_equal [hb, hb, hb], heartbeats
  end
end
