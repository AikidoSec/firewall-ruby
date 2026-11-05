# frozen_string_literal: true

module Aikido::Zen
  # Scans track information about a single call made by one of our Sinks
  # including whether it was detected as an attack.
  class Scan
    # @return [Aikido::Zen::Sink] the originating Sink.
    attr_reader :sink

    # @return [Aikido::Zen::Context] the current Context, wrapping the HTTP
    #   request during which this scan was performed.
    attr_reader :context

    # @return [Aikido::Zen::Attack, nil] a detected Attack, or
    #   +nil+ if the scan was considered safe.
    attr_reader :attack

    # @return [Array<Hash>] list of captured exceptions while scanning.
    attr_reader :errors

    # @param sink [Aikido::Zen::Sink]
    # @param context [Aikido::Zen::Context]
    def initialize(sink:, context:)
      @sink = sink
      @context = context
      @errors = []
      @performed = false
    end

    def performed?
      @performed
    end

    # @return [Boolean] whether this scan detected an Attack.
    def attack?
      @attack != nil
    end

    # @return [Boolean] whether any errors were caught by this Scan.
    def errors?
      @errors.any?
    end

    # Runs a block of code, capturing its return value as the potential
    # Attack object (or nil, if safe).
    #
    # @yieldreturn [Aikido::Zen::Attack, nil]
    # @return [void]
    def perform
      @performed = true
      @attack = yield
    end

    # Keep track of exceptions encountered during scanning.
    #
    # @param error [Exception]
    # @param scanner [#call]
    #
    # @return [nil]
    def track_error(error, scanner)
      @errors << {error: error, scanner: scanner}
      nil
    end
  end
end
