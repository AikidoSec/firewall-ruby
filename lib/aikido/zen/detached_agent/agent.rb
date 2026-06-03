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
  # @front_object object. Unfortunately, the methods to be called are
  # created at runtime by `DRbObject`, which leads to an ugly warning about
  # private methods after the delegator is bound.
  class Agent
    attr_reader :worker

    def initialize(
      config: Aikido::Zen.config,
      worker: Aikido::Zen::Worker.new(config: config),
      heartbeat_interval: 10,
      polling_interval: 10,
      collector: Aikido::Zen.collector
    )
      @config = config
      @worker = worker
      @heartbeat_interval = heartbeat_interval
      @polling_interval = polling_interval

      @collector = collector

      @front_object = DRbObject.new_with_uri(config.expanded_detached_agent_socket_uri)

      schedule_tasks
    end

    def send_collector_events
      events_data = @collector.flush_events.map(&:as_json)
      @front_object.send_collector_events(events_data)
    end

    def calculate_rate_limits(request)
      @front_object.calculate_rate_limits(request.route.as_json, request.client_ip, request.actor.as_json)
    end

    # Every time a fork occurs (a new child process is created), we need to start
    # a DRb service in a background thread within the child process. This service
    # will manage the connection and handle resource cleanup.
    def handle_fork
      DRb.start_service
      # we need to ensure that there are not more jobs in the queue, but
      # we reuse the same object
      @worker.restart
      schedule_tasks

      # Get a reference to the runtime settings
      # TODO: Rename #updated_settings
      Aikido::Zen.runtime_settings = @front_object.updated_settings
    end

    private

    def schedule_tasks
      @worker.every(@heartbeat_interval, run_now: false) do
        send_collector_events
      end
    end
  end
end
