# frozen_string_literal: true

require "drb/drb"
require "drb/unix"
require_relative "front_object"

module Aikido::Zen::DetachedAgent
  # It's possible to use `extend Forwardable` here for one-line forward calls to the
  # @detached_agent_front object. Unfortunately, the methods to be called are
  # created at runtime by `DRbObject`, which leads to an ugly warning about
  # private methods after the delegator is bound.
  class Agent
    def initialize(config: Aikido::Zen.config)
      @config = config
      @detached_agent_front = DRbObject.new_with_uri(config.detached_agent_socket_path)
    end

    def track_request
      @detached_agent_front.track_request
    rescue => e
      @config.logger.error(e.message)
    end

    def middleware_installed!
      @detached_agent_front.middleware_installed!
    rescue => e
      @config.logger.error(e.message)
    end

    def track_route(request)
      @detached_agent_front.track_route(request.route, request.schema.as_json)
    rescue => e
      @config.logger.error(e.message)
    end

    def track_outbound(outbound)
      @detached_agent_front.track_outbound(outbound)
    rescue => e
      @config.logger.error(e.message)
    end

    def track_scan(scan)
      @detached_agent_front.track_scan(scan.sink.name, scan.errors?, scan.duration)
    rescue => e
      @config.logger.error(e.message)
    end

    def track_user(user)
      @detached_agent_front.track_user(user.id, user.name, user.first_seen_at, user.ip)
    rescue => e
      @config.logger.error(e.message)
    end

    def track_attack(attack)
      @detached_agent_front.track_attack(attack.sink.name, attack.blocked?)
    rescue => e
      @config.logger.error(e.message)
    end

    # Every time a fork occurs (a new child process is created), we need to start
    # a DRb service in a background thread within the child process. This service
    # will manage the connection and handle resource cleanup.
    def handle_fork
      DRb.start_service
    end
  end
end
