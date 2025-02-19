# frozen_string_literal: true

require_relative "path_traversal/helpers"

module Aikido::Zen
  module Scanners
    class PathTraversalScanner
      # Checks if the user introduced input is trying to access other path using
      # Path Traversal kind of attacks.
      #
      # @param filepath [String] the expanded path that is tried to be read
      # @param context [Aikido::Zen::Context]
      # @param sink [Aikido::Zen::Sink] the Sink that is running the scan.
      # @param operation [Symbol, String] name of the method being scanned.
      #
      # @return [Aikido::Zen::Attacks::PathTraversalAttack, nil] an Attack if any
      # user input is detected to be attempting a Path Traversal Attack, or +nil+ if not.
      def self.call(filepath:, sink:, context:, operation:)
        return unless context

        context.payloads.each do |payload|
          next unless new(filepath, payload.value).attack?

          return Attacks::PathTraversalAttack.new(
            sink: sink,
            input: payload,
            filepath: filepath,
            context: context,
            operation: "#{sink.operation}.#{operation}"
          )
        end

        nil
      end

      def initialize(filepath, input)
        @filepath = filepath.downcase
        @input = input.downcase
      end

      def attack?
        # Single character are ignored because they don't pose a big threat
        return false if @input.length <= 1

        # We ignore cases where the user input is longer than the file path.
        # Because the user input can't be part of the file path.
        return false if @input.length > @filepath.length

        # We ignore cases where the user input is not part of the file path.
        return false unless @filepath.include?(@input)

        if PathTraversal::Helpers.contains_unsafe_path_parts(@filepath) && PathTraversal::Helpers.contains_unsafe_path_parts(@input)
          return true
        end

        # Check for absolute path traversal
        PathTraversal::Helpers.starts_with_unsafe_path(@filepath, @input)
      end
    end
  end
end
