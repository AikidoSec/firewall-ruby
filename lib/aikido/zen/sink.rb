# frozen_string_literal: true

require_relative "scan"

module Aikido::Zen
  module Sinks
    # @api internal
    # @return [Hash<String, Sink>]
    def self.registry
      @registry ||= {}
    end

    # Primary interface to set up a sink with a list of given scanners.
    #
    # @param name [String] name of the library being patched. (This must
    #   match the name of the gem, or we won't report that gem as
    #   supported.)
    # @param scanners [Array<#call>] a list of objects that respond to
    #   #call with a Hash and return an Attack or nil.
    # @param opts [Hash<Symbol, Object>] any other options to pass to
    #   the Sink initializer.
    #
    # @return [void]
    # @raise [ArgumentError] if a Sink with this name has already been
    #   registered.
    def self.add(name, scanners:, **opts)
      raise ArgumentError, "Sink #{name} already registered" if registry.key?(name.to_s)
      registry[name.to_s] = Sink.new(name.to_s, scanners: scanners, **opts)
    end
  end

  # Sinks serve as the proxies between a given library that we protect
  # (such as a database adapter that we patch to prevent SQL injections)
  # and the reporting agent.
  #
  # When a library is patched to track and potentially block attacks, we
  # rely on a sink to run any scans required, and report any attacks to
  # our agent.
  #
  # @see ./sinks/trilogy.rb for a reference implementation.
  class Sink
    # @return [String] name of the patched library (e.g. "mysql2").
    attr_reader :name

    # @return [Array<#call>] list of registered scanners for this sink.
    attr_reader :scanners

    # @return [String] descriptor of the module / method being scanned
    #   for attacks. This is fed into Attacks when instantiated. In
    #   certain cases, some scanners allow you to specialize this by
    #   using an +operation+ param of their own.
    attr_reader :operation

    DEFAULT_REPORTER = ->(scan) { Aikido::Zen.track_scan(scan) }

    def initialize(name, scanners:, operation: name, reporter: DEFAULT_REPORTER)
      raise ArgumentError, "scanners cannot be empty" if scanners.empty?

      @name = name
      @operation = operation
      @scanners = scanners
      @reporter = reporter
    end

    # Run the given arguments through all the registered scanners, until
    # one of them returns an Attack or all return +nil+, and report the
    # findings back to the Sink's +reporter+ to track statistics and
    # potentially handle the +Attack+, if anything.
    #
    # This checks if runtime protection has been turned off for the current
    # route first, and if so skips the scanning altogether, returning nil.
    #
    # @param scan_params [Hash] data to pass to all registered scanners.
    # @option scan_params [Aikido::Zen::Context, nil] :context
    #   The current Context, including the HTTP request being inspected, or
    #   +nil+ if we're scanning outside of an HTTP request.
    #
    # @return [Aikido::Zen::Scan, nil] the result of the scan, or +nil+ if the
    #   scan was skipped due to protection being disabled for the current route.
    # @raise [Aikido::UnderAttackError] if an attack is detected and
    #   blocking_mode is enabled.
    def scan(context: Aikido::Zen.current_context, **scan_params)
      return if context&.protection_disabled?

      scan = Scan.new(sink: self, context: context)

      scan.perform do
        result = nil

        scanners.each do |scanner|
          result = scanner.call(sink: self, context: context, **scan_params)
          break result if result
        rescue Aikido::Zen::InternalsError => error
          Aikido::Zen.config.logger.warn(error.message)
          scan.track_error(error, scanner)
        rescue => error
          scan.track_error(error, scanner)
        end

        result
      end

      @reporter.call(scan)

      scan
    end
  end
end
