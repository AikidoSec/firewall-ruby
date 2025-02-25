# frozen_string_literal: true

module Aikido::Zen::Scanners
  class ShellInjectionScanner
    # @param command [String]
    # @param sink [Aikido::Zen::Sink]
    # @param context [Aikido::Zen::Context]
    # @param operation [Symbol, String]
    #
    def self.call(command:, sink:, context:, operation:)
      return unless context

      context.payloads.each do |payload|
        next unless new(command, payload.value).attack?

        return Attacks::ShellInjectionAttack.new(
          sink: sink,
          input: payload,
          command: command,
          context: context,
          operation: "#{sink.operation}.#{operation}"
        )
      end

      nil
    end

    def initialize(command, input)
      @command = command
      @input = input
    end

    def attack?
      false
    end
  end
end
