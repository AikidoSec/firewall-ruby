# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require_relative "front_object"
require_relative "../background_worker"

module Aikido::Zen::DetachedAgent
  # It's possible to use `extend Forwardable` here for one-line forward calls to the
  # @detached_agent_front object. Unfortunately, the methods to be called are
  # created at runtime by `DRbObject`, which leads to an ugly warning about
  # private methods after the delegator is bound.
  class Agent
    def initialize(
      config: Aikido::Zen.config,
      collector: Aikido::Zen.collector,
      worker: Aikido::Zen::Worker.new(config: config)
    )
      @config = config
      @worker = worker
      @collector = collector
      @detached_agent_front = DRbObject.new_with_uri(config.detached_agent_socket_path)

      schedule_tasks
    end

    def send_heartbeat(at: Time.now.utc)
      return unless @collector.stats.any?

      heartbeat = @collector.flush(at: at)
      @config.logger.debug("Sending heartbeat from child [#{Process.pid}] to parent process [#{Process.ppid}]")
      @detached_agent_front.send_heartbeat_to_parent_process(heartbeat.to_json)
    end

    private def schedule_tasks
      @worker.every(10, run_now: false) { send_heartbeat }
    end

    # Every time a fork occurs (a new child process is created), we need to start
    # a DRb service in a background thread within the child process. This service
    # will manage the connection and handle resource cleanup.
    def handle_fork
      DRb.start_service
      @worker.shutdown
      @worker = Aikido::Zen::Worker.new(config: @config)
      schedule_tasks
    end
  end
end
