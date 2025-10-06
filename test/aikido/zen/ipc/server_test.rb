# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::IPC::ServerTest < ActiveSupport::TestCase
  FakeDrbServer = Struct.new(:stopped, :attempts) do
    def initialize(max_attempts)
      super
      self[:stopped] = false
      self[:attempts] = 0
      @max_attempts = max_attempts
    end

    def alive?
      self[:attempts] += 1
      self[:attempts] >= @max_attempts
    end

    def stop_service
      self[:stopped] = true
    end

    def verbose=(v)
    end
  end

  test "server starts after a certain number of retries" do
    @fake_drb_server = FakeDrbServer.new(4)

    DRb.stub(:start_service, @fake_drb_server) do
      Aikido::Zen::IPC::Server.start
    end
    assert_equal 4, @fake_drb_server.attempts
  end

  test "An exception is raised in case we exhaust the max number of attempts while starting the server" do
    @fake_drb_server = FakeDrbServer.new(11)
    DRb.stub(:start_service, @fake_drb_server) do
      assert_raises Aikido::Zen::IPCError do
        Aikido::Zen::IPC::Server.start
      end
    end
  end

  test "Server is stopped " do
    @fake_drb_server = FakeDrbServer.new(2)
    DRb.stub(:start_service, @fake_drb_server) do
      server = Aikido::Zen::IPC::Server.start
      server.stop!
    end
    assert @fake_drb_server.stopped
  end
end
