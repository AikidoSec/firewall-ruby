# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::AgentTest < ActiveSupport::TestCase
  include WorkerHelpers

  class MockAPIClient < Aikido::Zen::APIClient
    def should_fetch_settings?
      false
    end

    def fetch_runtime_config
      {}
    end

    def fetch_runtime_firewall_lists
      {}
    end

    def report(event)
      {}
    end
  end

  setup do
    @config = Aikido::Zen.config
    @config.api_token = "TOKEN"

    @api_client = Minitest::Mock.new(MockAPIClient.new)
    @collector = Aikido::Zen.collector
    @worker = MockWorker.new

    @agent = Aikido::Zen::Agent.new(
      api_client: @api_client,
      collector: @collector,
      worker: @worker
    )

    @test_sink = Aikido::Zen::Sink.new("test", scanners: [NOOP])
  end

  teardown do
    @agent.stop!
  end

  test "knows if it has started" do
    refute @agent.started?

    @agent.start!
    assert @agent.started?

    @agent.stop!
    refute @agent.started?
  end

  test "#start! fails if attempted to start multiple times" do
    @agent.start!

    err = assert_raises Aikido::ZenError do
      @agent.start!
    end

    assert_match(/already started/i, err.message)
  end

  test "#start! sets the start time for our stats funnel" do
    assert_changes "@collector.stats.started_at", from: nil do
      @agent.start!
    end
  end

  test "#start! warns if blocking mode is disabled" do
    @config.blocking_mode = false
    @agent.start!

    assert_logged :warn, /non-blocking mode enabled! no requests will be blocked/i
    refute_logged :info, /requests identified as attacks will be blocked/i
  end

  test "#start! notifies if blocking mode is enabled" do
    @config.blocking_mode = true
    @agent.start!

    refute_logged :warn, /non-blocking mode enabled! no requests will be blocked/i
    assert_logged :info, /requests identified as attacks will be blocked/i
  end

  test "#start! notifies if an API token has been set" do
    @config.api_token = "TOKEN"
    @agent.start!

    assert_logged :debug, /api token set! reporting has been enabled/i
    refute_logged :warn, /no api token set! reporting has been disabled/i
  end

  test "#start! warns if there's no API token set" do
    @config.api_token = nil
    @agent.start!

    assert_logged :warn, /no api token set! reporting has been disabled/i
    refute_logged :debug, /api token set! reporting has been enabled/i
  end

  test "#start! reports a STARTED event" do
    @api_client.expect :report, {}, [Aikido::Zen::Events::Started]

    @agent.start!

    assert_mock @api_client
  end

  test "#start! takes the response of the STARTED event as runtime settings" do
    @api_client.expect :report,
      {"configUpdatedAt" => 1234567890000},
      [Aikido::Zen::Events::Started]

    assert_changes -> { Aikido::Zen.runtime_settings.updated_at }, to: Time.at(1234567890) do
      @agent.start!
    end

    assert_mock @api_client
    assert_logged :info, /updated runtime settings/i
  end

  test "#start! does not report a STARTED event if it does not have an API token" do
    @config.api_token = nil

    def @api_client.report(event)
      raise "Should not report anything"
    end

    assert_nothing_raised do
      @agent.start!
    end
  end

  test "#start! starts polling for setting updates every minute" do
    @api_client.expect :should_fetch_settings?, false

    assert_difference "@worker.jobs.size", +1 do
      @agent.start!
    end

    timer = @worker.jobs.first
    assert_equal @config.polling_interval, timer.execution_interval

    refute_logged :info, /updated runtime settings after polling/i

    assert_mock @api_client
  end

  test "#start! updates the runtime settings after polling if needed" do
    @api_client.expect :should_fetch_settings?, true
    @api_client.expect :fetch_runtime_config, {"configUpdatedAt" => 1234567890000}

    assert_changes -> { Aikido::Zen.runtime_settings.updated_at }, to: Time.at(1234567890) do
      @agent.start!
    end

    assert_logged :info, /updated runtime settings after polling/i

    assert_mock @api_client
  end

  test "#handle_attack logs the attack's message" do
    attack = TestAttack.new(sink: @test_sink)

    @agent.handle_attack(attack)

    assert_logged :error,
      'Zen has detected a humanized test attack name: {"kind":"test_attack","blocked":false,"metadata":{"extra_metadata":"value"},"operation":"test","payload":"value","source":null,"path":".path"}'
  end

  test "#handle_attack reports an ATTACK event" do
    @api_client.expect :report, {}, [Aikido::Zen::Events::Attack]

    @agent.handle_attack(TestAttack.new(sink: @test_sink))

    assert_mock @api_client
  end

  test "#handle_attack does not report an event if the API can't make requests" do
    @config.api_token = nil

    @agent.stub :report, -> { raise "#report called unexpectedly" } do
      assert_nothing_raised do
        @agent.handle_attack(TestAttack.new(sink: @test_sink))
      end
    end
  end

  test "#handle_attack raises an error if blocking_mode is configured" do
    @config.blocking_mode = true

    attack = TestAttack.new(sink: @test_sink)

    assert_raises Aikido::Zen::UnderAttackError do
      @agent.handle_attack(attack)
    end
  end

  test "#handle_attack marks that the attack will be blocked before reporting the event" do
    @config.blocking_mode = true

    agent = Minitest::Mock.new(@agent)
    agent.expect :report, {} do |event|
      assert event.attack.blocked?
    end

    assert_raises Aikido::Zen::UnderAttackError do
      attack = TestAttack.new(sink: @test_sink)
      agent.handle_attack(attack)
    end
  end

  test "#handle_attack does not raise if blocking_mode is off" do
    @config.blocking_mode = false

    attack = TestAttack.new(sink: @test_sink)

    assert_nothing_raised do
      @agent.handle_attack(attack)
    end
  end

  test "#handle_attack does not mark that the attack was blocked if blocking_mode is off" do
    @config.blocking_mode = false

    agent = Minitest::Mock.new(@agent)
    agent.expect :report, {} do |event|
      refute event.attack.blocked?
    end

    assert_nothing_raised do
      attack = TestAttack.new(sink: @test_sink)
      agent.handle_attack(attack)
    end
  end

  test "#send_heartbeat reports a heartbeat event and updates the settings" do
    event = Aikido::Zen::Collector::Events::TrackRequest.new

    @collector.add_event(event)

    @api_client.expect :report, {"receivedAnyStats" => true} do |heartbeat|
      heartbeat.is_a?(Aikido::Zen::Events::Heartbeat)
    end

    assert_changes -> { Aikido::Zen.runtime_settings.received_any_stats }, to: true do
      @agent.send_heartbeat
    end

    assert_mock @api_client
  end

  test "#send_heartbeat flushes events when sending the heartbeat" do
    event = Aikido::Zen::Collector::Events::TrackRequest.new

    @collector.add_event(event)

    assert @collector.has_events?

    @agent.send_heartbeat

    refute @collector.has_events?
  end

  test "#send_heartbeat does nothing if we don't have an API token" do
    @config.api_token = nil

    @agent.stub :report, -> { raise "#report called unexpectedly" } do
      assert_nothing_raised do
        @agent.send_heartbeat
      end
    end
  end

  test "#send_heartbeat does not try to update stats if the API returns null" do
    event = Aikido::Zen::Collector::Events::TrackRequest.new

    # this happens e.g. when events are rate limited
    @api_client.expect :report, nil do |heartbeat|
      heartbeat.is_a?(Aikido::Zen::Events::Heartbeat)
    end

    @collector.add_event(event)

    assert_nothing_raised do
      @agent.send_heartbeat
    end

    refute_logged :info, /Updated runtime settings after heartbeat/

    assert_mock @api_client
  end

  test "#updated_settings! configures a timer for the configured frequency" do
    Aikido::Zen.runtime_settings.heartbeat_interval = 10

    assert_difference "@worker.jobs.size", +1 do
      @agent.updated_settings!
    end

    timer = @worker.jobs.first
    assert_equal 10, timer.execution_interval

    assert_logged :debug, /scheduling heartbeats every 10 seconds/i
  end

  test "#updated_settings! resets the timer if the interval changes" do
    settings = Aikido::Zen.runtime_settings
    settings.heartbeat_interval = 10
    assert_difference "@worker.jobs.size", +1 do
      @agent.updated_settings!
    end

    first_timer = @worker.jobs.last
    assert_equal 10, first_timer.execution_interval
    assert first_timer.running?

    settings.heartbeat_interval = 20
    assert_difference "@worker.jobs.size", +1 do
      @agent.updated_settings!
    end

    second_timer = @worker.jobs.last
    assert_equal 20, second_timer.execution_interval
    refute first_timer.running?
    assert second_timer.running?
  end

  test "#start! queues a one-off tasks for each initial heartbeat delay" do
    size = @config.initial_heartbeat_delays.size

    assert_difference "@worker.delayed.size", size do
      @agent.start!
    end

    tasks = @worker.delayed.last(size)

    size.times do |i|
      assert_equal @config.initial_heartbeat_delays[i], tasks[i].initial_delay
      assert tasks[i].pending? # is queued for execution
    end
  end

  test "#start! successfully sends the initial heartbeats" do
    # Make sure there are _some_ stats
    @collector.track_request

    # Ignore the actual delay
    def @worker.delay(*)
      yield
    end

    heartbeat_sent = false

    @agent.stub(:send_heartbeat, -> { heartbeat_sent = true }) do
      @agent.start!
    end

    assert heartbeat_sent
  end

  test "#updated_settings! does not queue a one-off task if the server received stats" do
    settings = Aikido::Zen.runtime_settings
    settings.received_any_stats = true

    assert_no_difference "@worker.delayed.size" do
      @agent.updated_settings!
    end

    assert_empty @worker.delayed
  end

  test "#report logs API errors" do
    event = Aikido::Zen::Event.new(type: "test")

    @api_client.expect :report, nil do |_|
      request = Net::HTTP::Post.new("/")
      response = OpenStruct.new(code: "400", message: "Bad request", body: "")

      raise Aikido::Zen::APIError.new(request, response)
    end

    assert_nothing_raised { @agent.report(event) }

    assert_logged :error, %r{Error in POST /: 400 Bad request}i

    assert_mock @api_client
  end

  test "#report logs network errors" do
    event = Aikido::Zen::Event.new(type: "test")

    @api_client.expect :report, nil do |_|
      request = Net::HTTP::Post.new("/")
      error = Net::ReadTimeout.new("test")
      raise Aikido::Zen::NetworkError.new(request, error)
    end

    assert_nothing_raised { @agent.report(event) }

    assert_logged :error, %r{Error in POST /: Net::ReadTimeout with "test"}i

    assert_mock @api_client
  end

  class TestAttack < Aikido::Zen::Attack
    def initialize(sink: nil, context: nil, operation: "test")
      super
    end

    def metadata
      {extra_metadata: "value"}
    end

    def humanized_name
      "humanized test attack name"
    end

    def kind
      "test_attack"
    end

    def input
      Aikido::Zen::Payload.new("value", "source", "path")
    end

    def exception(*)
      Aikido::Zen::UnderAttackError.new(self)
    end
  end

  def stub_context(path = "/", env = {})
    env = Rack::MockRequest.env_for(path, {"REQUEST_METHOD" => "GET"}.merge(env))
    Aikido::Zen.current_context = Aikido::Zen::Context.from_rack_env(env)
  end

  def stub_request(path = "/", env = {})
    stub_context(path, env).request
  end
end
