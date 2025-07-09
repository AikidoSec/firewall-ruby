# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module Kernel
      def self.load_sinks!
        ::Kernel.singleton_class.prepend(KernelExtensions)
        ::Kernel.prepend(KernelExtensions)
      end

      SINK = Sinks.add("Kernel", scanners: [Scanners::ShellInjectionScanner])

      module Helpers
        def self.scan(command, operation)
          SINK.scan(command: command, operation: operation)
        end
      end

      module KernelExtensions
        extend Sinks::DSL

        %i[system spawn].each do |method_name|
          sink_before method_name do |*args|
            # Remove the optional environment argument before the command-line.
            args.shift if args.first.is_a?(Hash)
            Helpers.scan(args.first, method_name)
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Kernel.load_sinks!
