# frozen_string_literal: true

module Aikido::Zen::Sinks
  module Kernel
    SINK = Sinks.add("Kernel", scanners: [
      Aikido::Zen::Scanners::ShellInjectionScanner
    ])

    module Extensions
      def self.scan_command(command, operation)
        SINK.scan(
          command: command,
          operation: operation
        )
      end

      def system(*args)
        pp args
        super
      end
    end
  end
end

::Kernel.singleton_class.prepend Aikido::Zen::Sinks::Kernel::Extensions
