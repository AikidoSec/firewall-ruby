# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module Kernel
      SINK = Sinks.add("Kernel", scanners: [
        Aikido::Zen::Scanners::ShellInjectionScanner
      ])

      module Extensions
        # Checks if the user introduced input is trying to execute other commands
        # using Shell Injection kind of attacks.
        #
        # @param command [String] the _full command_ that will be executed.
        # @param context [Aikido::Zen::Context]
        # @param sink [Aikido::Zen::Sink] the Sink that is running the scan.
        # @param operation [Symbol, String] name of the method being scanned.
        #
        # @return [Aikido::Zen::Attacks::ShellInjectionAttack, nil] an Attack if any
        # user input is detected to be attempting a Shell Injection Attack, or +nil+ if not.
        def self.scan_command(command, operation)
          SINK.scan(
            command: command,
            operation: operation
          )
        end

        # `system, spawn` functions can be invoked in several ways. For more details,
        # see [the documentation](https://apidock.com/ruby/Kernel/spawn)
        #
        # In our context, we care primarily about two common scenarios:
        #   - one argument (String)
        #       e.g.: system("ls"), system("echo something")
        #   - two arguments (Hash, String)
        #       e.g.: system({"foo" => "bar"}, "ls"), system({"foo" => "bar"}, "echo something")
        #
        # In all other cases, Ruby's default behavior ensures that user input is appropriately
        # escaped, mitigating injection risks. Specifically:
        #
        # If a user input contains something like $(whoami) and is passed as part of the command
        # arguments (e.g., user_input = "$(whoami)"):
        #
        #   system("echo", user_input)   This is safe because Ruby automatically escapes arguments
        #                                passed to system/spawn in this form.
        #
        #   system("echo #{user_input}") This is not safe because Ruby interpolates the user_input
        #                                into the command string, resulting in a potentially harmful
        #                                command like `echo $(whoami)`.
        def send_arg_to_scan(args, operation)
          if args.size == 1 && args[0].is_a?(String)
            Extensions.scan_command(args[0], operation)
          end

          if args.size == 2 && args[0].is_a?(Hash)
            Extensions.scan_command(args[1], operation)
          end
        end

        def system(*args, **)
          send_arg_to_scan(args, "system")
          super
        end

        def spawn(*args, **)
          send_arg_to_scan(args, "spawn")
          super
        end
      end
    end
  end
end

::Kernel.singleton_class.prepend Aikido::Zen::Sinks::Kernel::Extensions
::Kernel.prepend Aikido::Zen::Sinks::Kernel::Extensions
