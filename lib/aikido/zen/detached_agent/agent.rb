# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require_relative "front_object"
require_relative "../background_worker"

module Aikido::Zen::DetachedAgent
  # Agent that runs in forked processes. It communicates with the parent process to dRB
  # calls. It's in charge of schedule and send heartbeats to the *parent process*, to be
  # later pushed.
  #
  # It's possible to use `extend Forwardable` here for one-line forward calls to the
  # @detached_agent_front object. Unfortunately, the methods to be called are
  # created at runtime by `DRbObject`, which leads to an ugly warning about
  # private methods after the delegator is bound.
  class Agent
    attr_reader :worker

    def initialize(
      heartbeat_interval: 10,
      config: Aikido::Zen.config,
      collector: Aikido::Zen.collector,
      worker: Aikido::Zen::Worker.new(config: config)
    )
      @config = config
      @heartbeat_interval = heartbeat_interval
      @worker = worker
      @collector = collector
      @detached_agent_front = DRbObject.new_with_uri(config.detached_agent_socket_path)

      schedule_tasks
    end

    def send_heartbeat(at: Time.now.utc)
      return unless @collector.stats.any?

      heartbeat = @collector.flush(at: at)
      @detached_agent_front.send_heartbeat_to_parent_process(heartbeat.as_json)
    end

    private def schedule_tasks
      @worker.every(@heartbeat_interval, run_now: false) { send_heartbeat }
    end

    def calculate_rate_limits(request)
      @detached_agent_front.calculate_rate_limits(request.route, request.ip, request.actor.to_json)
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
