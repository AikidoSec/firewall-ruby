# frozen_string_literal: true

module Aikido::Zen
  # @api private
  #
  # Tracks data specific to a single Sink.
  class Collector::SinkStats
    # @return [String] category of operation this sink represents.
    attr_accessor :kind

    # @return [Integer] number of total calls to Sink#scan.
    attr_accessor :scans

    # @return [Integer] number of scans where our scanners raised an
    #   error that was handled.
    attr_accessor :errors

    # @return [Integer] number of scans where an attack was detected.
    attr_accessor :attacks

    # @return [Integer] number of scans where an attack was detected
    #   _and_ blocked by the Zen.
    attr_accessor :blocked_attacks

    def initialize(name)
      @name = name

      @scans = 0
      @errors = 0

      @attacks = 0
      @blocked_attacks = 0
    end

    def as_json
      {
        "kind" => @kind,
        "total" => @scans,
        "interceptorThrewError" => @errors,
        "withoutContext" => 0,
        "attacksDetected" => {
          "total" => @attacks,
          "blocked" => @blocked_attacks
        }
      }
    end
  end
end
