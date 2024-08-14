# frozen_string_literal: true

module Aikido::Firewall
  # Attack objects gather information about a type of detected attack.
  # They can be used in a few ways, like for reporting an attack event
  # to the Aikido server, or can be raised as errors to block requests
  # if blocking_mode is on.
  class Attack
    attr_reader :request
    attr_accessor :sink

    def initialize(request:, sink:)
      @request = request
      @sink = sink
    end

    def log_message
      raise NotImplementedError, "implement in subclasses"
    end

    def as_json
      raise NotImplementedError, "implement in subclasses"
    end

    def exception(*)
      raise NotImplementedError, "implement in subclasses"
    end
  end
end
