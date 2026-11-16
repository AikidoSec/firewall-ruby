# frozen_string_literal: true

require_relative "shell_injection/helpers"

module Aikido::Zen
  module Scanners
    class ShellInjectionScanner
      def self.skips_on_nil_context?
        true
      end

      # @param command [String]
      # @param scan [Aikido::Zen::Scan]
      # @param sink [Aikido::Zen::Sink]
      # @param context [Aikido::Zen::Context]
      # @param operation [Symbol, String]
      # @return [Aikido::Zen::Attacks::ShellInjectionAttack, nil] the attack,
      #   or nil if there was none.
      def self.call(command:, scan:, sink:, context:, operation:)
        scanner = new(command)

        context.payloads.each do |payload|
          next unless scanner.attack?(payload.value.to_s)

          return Attacks::ShellInjectionAttack.new(
            sink: sink,
            input: payload,
            command: command,
            context: context,
            operation: "#{sink.operation}.#{operation}",
            stack: Aikido::Zen.clean_stack_trace
          )
        rescue => error
          scan.track_error(error, self)
        end

        nil
      end

      # @param command [String] the command to check.
      def initialize(command)
        @command = Aikido::Zen::Helpers.encode_safely(command)
      end

      # @param input [String] the input to check.
      # @return [Boolean] whether the input was an attack.
      def attack?(input)
        # Block single ~ character. For example `echo ~`
        if input == "~"
          if @command.size > 1 && @command.include?("~")
            return true
          end
        end

        # we ignore single character since they don't pose a big threat.
        # They are only able to crash the shell, not execute arbitraty commands.
        return false if input.size <= 1

        # We ignore cases where the user input is longer than the command because
        # the user input can't be part of the command
        return false if input.size > @command.size

        return false unless @command.include?(input)

        return false if ShellInjection::Helpers.is_safely_encapsulated @command, input

        ShellInjection::Helpers.contains_shell_syntax @command, input
      end
    end
  end
end
