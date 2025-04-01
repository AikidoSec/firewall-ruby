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
  # heartbeat & polling interval are configured to 10s , because they are connecting with
  # parent process. We want to have the freshest data.
  #
  # It's possible to use `extend Forwardable` here for one-line forward calls to the
  # @detached_agent_front object. Unfortunately, the methods to be called are
  # created at runtime by `DRbObject`, which leads to an ugly warning about
  # private methods after the delegator is bound.
  class Agent
    attr_reader :worker

    def initialize(
      heartbeat_interval: 10,
      polling_interval: 10,
      config: Aikido::Zen.config,
      collector: Aikido::Zen.collector,
      worker: Aikido::Zen::Worker.new(config: config)
    )
      @config = config
      @heartbeat_interval = heartbeat_interval
      @polling_interval = polling_interval
      @worker = worker
      @collector = collector
      @detached_agent_front = DRbObject.new_with_uri(config.detached_agent_socket_path)
      @has_forked = false
      schedule_tasks
    end

    def send_heartbeat(at: Time.now.utc)
      return unless @collector.stats.any?

      heartbeat = @collector.flush(at: at)
      @detached_agent_front.send_heartbeat_to_parent_process(heartbeat.as_json)
    end

    private def schedule_tasks
      # For heartbeats is correct to send them from parent or child process. Otherwise, we'll lose
      # stats made by the parent process.
      @worker.every(@heartbeat_interval, run_now: false) { send_heartbeat }

      # Runtime_settings fetch must happens only in the child processes, otherwise, due to
      # we are updating the global runtime_settings, we could have an infinite recursion.
      if @has_forked
        @worker.every(@polling_interval) do
          Aikido::Zen.runtime_settings = @detached_agent_front.updated_settings
          @config.logger.debug "Updated runtime settings after polling from child process #{Process.pid}"
        end
      end
    end

    def calculate_rate_limits(request)
      @detached_agent_front.calculate_rate_limits(request.route, request.ip, request.actor.to_json)
    end

    # Every time a fork occurs (a new child process is created), we need to start
    # a DRb service in a background thread within the child process. This service
    # will manage the connection and handle resource cleanup.
    def handle_fork
      @has_forked = true
      DRb.start_service
      @worker.shutdown
      @worker = Aikido::Zen::Worker.new(config: @config)
      schedule_tasks
    end
  end
end
