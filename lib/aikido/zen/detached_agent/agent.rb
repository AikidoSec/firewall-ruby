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
    def initialize(config: Aikido::Zen.config)
      @config = config
      @detached_agent_front = DRbObject.new_with_uri(config.detached_agent_socket_path)
      @background_worker = Aikido::Zen::BackgroundWorker.new do |work|
        work.call
      rescue => e
        @config.logger.error(e)
      end

      @background_worker.start
    end

    def track_request
      @background_worker.enqueue(-> {
        @detached_agent_front.track_request
      })
    end

    def middleware_installed!
      @detached_agent_front.middleware_installed!
    end

    def track_route(request)
      # schema is a complex object, which must be converted to a hash outside the enqueue ->()
      # otherwise it might GC-ed.
      schema = request.schema.as_json
      @background_worker.enqueue(-> {
        @detached_agent_front.track_route(request.route, schema)
      })
    end

    def track_outbound(outbound)
      @background_worker.enqueue(-> {
        @detached_agent_front.track_outbound(outbound)
      })
    end

    def track_scan(scan)
      @background_worker.enqueue(-> {
        @detached_agent_front.track_scan(scan.sink.name, scan.errors?, scan.duration)
      })
    end

    def track_user(user)
      @background_worker.enqueue(-> {
        @detached_agent_front.track_user(user.id, user.name, user.first_seen_at, user.ip)
      })
    end

    def track_attack(attack)
      @background_worker.enqueue(-> {
        @detached_agent_front.track_attack(attack.sink.name, attack.blocked?)
      })
    end

    # Every time a fork occurs (a new child process is created), we need to start
    # a DRb service in a background thread within the child process. This service
    # will manage the connection and handle resource cleanup.
    def handle_fork
      @background_worker.restart
      DRb.start_service
    end
  end
end
