# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module Kernel
      SINK = Sinks.add("Kernel", "exec_op", scanners: [Scanners::ShellInjectionScanner])

      module Helpers
        def self.scan(command, operation)
          SINK.scan(command: command, operation: operation)
        end

        def self.scan_all_args(args, operation)
          # Scan all command arguments that could contain shell commands.
          # When system/spawn is called with multiple arguments like:
          # system("sh", "-c", user_input), the user_input is executed by the shell
          # and must be scanned for injection attacks.
          args.each do |arg|
            # Skip non-string arguments (e.g., keyword arguments hash at the end)
            next unless arg.is_a?(String)
            scan(arg, operation)
          end
        end
      end

      def self.load_sinks!
        [::Kernel.singleton_class, ::Kernel].each do |klass|
          klass.class_eval do
            extend Sinks::DSL

            %i[system spawn `].each do |method_name|
              sink_before method_name do |*args|
                # Remove the optional environment argument before the command-line.
                args.shift if args.first.is_a?(Hash)
                # Scan all arguments, not just the first one, to prevent bypasses
                # like system("sh", "-c", user_input) where user_input is in args[2]
                Helpers.scan_all_args(args, method_name)
              end
            end
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Kernel.load_sinks!
