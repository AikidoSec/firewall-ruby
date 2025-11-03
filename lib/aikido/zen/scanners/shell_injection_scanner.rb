# frozen_string_literal: true

require_relative "shell_injection/helpers"

module Aikido::Zen
  module Scanners
    class ShellInjectionScanner
      def self.skips_on_nil_context?
        true
      end

      # @param command [String]
      # @param sink [Aikido::Zen::Sink]
      # @param context [Aikido::Zen::Context]
      # @param operation [Symbol, String]
      #
      def self.call(command:, sink:, context:, operation:)
        context.payloads.each do |payload|
          next unless new(command, payload.value).attack?

          return Attacks::ShellInjectionAttack.new(
            sink: sink,
            input: payload,
            command: command,
            context: context,
            operation: "#{sink.operation}.#{operation}",
            stack: Aikido::Zen.clean_stack_trace
          )
        end

        nil
      end

      # @param command [String]
      # @param input [String]
      def initialize(command, input)
        @command = command
        @input = input
      end

      def attack?
        # Block single ~ character. For example `echo ~`
        if @input == "~"
          if @command.size > 1 && @command.include?("~")
            return true
          end
        end

        # we ignore single character since they don't pose a big threat.
        # They are only able to crash the shell, not execute arbitraty commands.
        return false if @input.size <= 1

        # We ignore cases where the user input is longer than the command because
        # the user input can't be part of the command
        return false if @input.size > @command.size

        return false unless @command.include?(@input)

        return false if ShellInjection::Helpers.is_safely_encapsulated @command, @input

        ShellInjection::Helpers.contains_shell_syntax @command, @input
      end
    end
  end
end
