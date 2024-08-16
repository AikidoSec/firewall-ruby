# frozen_string_literal: true

require "test_helper"

class Aikido::Agent::RunnerTest < ActiveSupport::TestCase
  # Make it easier to test
  Aikido::Agent::Runner.attr_reader :timer_tasks

  class MockAPIClient < Aikido::Agent::APIClient
    def should_fetch_settings?
      false
    end

    def fetch_settings
      {}
    end

    def report(event)
      {}
    end
  end

  setup do
    @config = Aikido::Agent.config
    @config.api_token = "TOKEN"

    @api_client = Minitest::Mock.new(MockAPIClient.new)
    @runner = Aikido::Agent::Runner.new(api_client: @api_client)

    @test_sink = Aikido::Firewall::Sink.new("test", scanners: [NOOP])
  end

  teardown do
    @runner.stop!
  end

  test "knows if it has started" do
    refute @runner.started?

    @runner.start!
    assert @runner.started?

    @runner.stop!
    refute @runner.started?
  end

  test "#start! fails if attempted to start multiple times" do
    @runner.start!

    err = assert_raises Aikido::AgentError do
      @runner.start!
    end

    assert_match(/already started/i, err.message)
  end

  test "#start! sets the start time for our stats funnel" do
    assert_nil @runner.stats.started_at

    @runner.start!

    refute_nil @runner.stats.started_at
  end

  test "#start! warns if blocking mode is disabled" do
    @config.blocking_mode = false
    @runner.start!

    assert_logged :warn, /non-blocking mode enabled! no requests will be blocked/i
    refute_logged :info, /requests identified as attacks will be blocked/i
  end

  test "#start! notifies if blocking mode is enabled" do
    @config.blocking_mode = true
    @runner.start!

    refute_logged :warn, /non-blocking mode enabled! no requests will be blocked/i
    assert_logged :info, /requests identified as attacks will be blocked/i
  end

  test "#start! notifies if an API token has been set" do
    @config.api_token = "TOKEN"
    @runner.start!

    assert_logged :debug, /api token set! reporting has been enabled/i
    refute_logged :warn, /no api token set! reporting has been disabled/i
  end

  test "#start! warns if there's no API token set" do
    @config.api_token = nil
    @runner.start!

    assert_logged :warn, /no api token set! reporting has been disabled/i
    refute_logged :debug, /api token set! reporting has been enabled/i
  end

  test "#start! reports a STARTED event" do
    @runner.stub :reporting_pool, Concurrent::ImmediateExecutor.new do
      @api_client.expect :report, {}, [Aikido::Agent::Events::Started]

      @runner.start!

      assert_mock @api_client
    end
  end

  test "#start! takes the response of the STARTED event as firewall settings" do
    @runner.stub :reporting_pool, Concurrent::ImmediateExecutor.new do
      @api_client.expect :report,
        {"configUpdatedAt" => 1234567890000},
        [Aikido::Agent::Events::Started]

      assert_changes -> { Aikido::Firewall.settings.updated_at }, to: Time.at(1234567890) do
        @runner.start!
      end

      assert_mock @api_client
      assert_logged :info, /updated firewall settings/i
    end
  end

  test "#start! does not report a STARTED event if it does not have an API token" do
    @config.api_token = nil

    def @api_client.report(event)
      raise "Should not report anything"
    end

    assert_nothing_raised do
      @runner.start!
    end
  end

  test "#start! starts polling for setting updates every minute" do
    @runner.stub :reporting_pool, Concurrent::ImmediateExecutor.new do
      @api_client.expect :should_fetch_settings?, false

      assert_difference -> { @runner.timer_tasks.size }, +1 do
        @runner.start!
      end

      timer = @runner.timer_tasks.first
      assert_equal @config.polling_interval, timer.execution_interval

      refute_logged :info, /updated firewall settings after polling/i

      assert_mock @api_client
    end
  end

  test "#start! updates the firewall settings after polling if needed" do
    @runner.stub :reporting_pool, Concurrent::ImmediateExecutor.new do
      @api_client.expect :should_fetch_settings?, true
      @api_client.expect :fetch_settings, {"configUpdatedAt" => 1234567890000}

      assert_changes -> { Aikido::Firewall.settings.updated_at }, to: Time.at(1234567890) do
        @runner.start!
      end

      assert_logged :info, /updated firewall settings after polling/i

      assert_mock @api_client
    end
  end

  test "#handle_attack logs the attack's message" do
    attack = TestAttack.new(sink: @test_sink)

    @runner.handle_attack(attack)

    assert_logged :error, /\[ATTACK DETECTED\] test attack/
  end

  test "#handle_attack reports an ATTACK event" do
    attack = TestAttack.new(sink: @test_sink)

    @runner.stub :reporting_pool, Concurrent::ImmediateExecutor.new do
      @api_client.expect :report, {}, [Aikido::Agent::Events::Attack]

      @runner.handle_attack(attack)

      assert_mock @api_client
    end
  end

  test "#handle_attack does not report an event if the API can't make requests" do
    @config.api_token = nil

    @runner.stub :report, -> { raise "#report called unexpectedly" } do
      assert_nothing_raised do
        @runner.handle_attack(TestAttack.new(sink: @test_sink))
      end
    end
  end

  test "#handle_attack raises an error if blocking_mode is configured" do
    @config.blocking_mode = true

    attack = TestAttack.new(sink: @test_sink)

    assert_raises Aikido::Firewall::UnderAttackError do
      @runner.handle_attack(attack)
    end
  end

  test "#send_heartbeat reports a heartbeat event and updates the settings" do
    @runner.stub :reporting_pool, Concurrent::ImmediateExecutor.new do
      @api_client.expect :report, {"receivedAnyStats" => true}, [Aikido::Agent::Events::Heartbeat]

      assert_changes -> { Aikido::Firewall.settings.received_any_stats }, to: true do
        @runner.send_heartbeat
      end

      assert_mock @api_client
    end
  end

  test "#send_heartbeat flushes the stats before sending them" do
    stats = Minitest::Mock.new
    stats.expect :serialize_and_reset, {}

    @runner.stub :stats, stats do
      @runner.send_heartbeat

      assert_mock stats
    end
  end

  test "#send_heartbeat does nothing if we don't have an API token" do
    @config.api_token = nil

    @runner.stub :report, -> { raise "#report called unexpectedly" } do
      assert_nothing_raised do
        @runner.send_heartbeat
      end
    end
  end

  test "#setup_heartbeat configures a timer for the configured frequency" do
    settings = Aikido::Firewall.settings
    settings.heartbeat_interval = 10

    assert_difference -> { @runner.timer_tasks.size }, +1 do
      @runner.setup_heartbeat(settings)
    end

    timer = @runner.timer_tasks.last
    assert_equal 10, timer.execution_interval

    assert_logged :debug, /scheduling heartbeats every 10 seconds/i
  end

  class TestAttack < Aikido::Firewall::Attack
    def initialize(sink: nil, request: nil)
      super
    end

    def log_message
      "test attack"
    end

    def as_json
      {}
    end

    def exception(*)
      Aikido::Firewall::UnderAttackError.new(self)
    end
  end
end
