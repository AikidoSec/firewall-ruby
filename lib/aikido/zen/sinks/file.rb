# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module File
      SINK = Sinks.add("File", scanners: [Scanners::PathTraversalScanner])

      module Helpers
        def self.scan(filepath, operation)
          SINK.scan(
            filepath: filepath,
            operation: operation
          )
        end
      end

      def self.load_sinks!
        ::File.singleton_class.class_eval do
          extend Sinks::DSL

          # Create a copy of the original methods for internal use only to prevent
          # recursion in PathTraversalScanner.
          #
          # IMPORTANT: The aliases must be created before the method is overridden.
          alias_method :expand_path__internal_for_aikido_zen, :expand_path
          alias_method :join__internal_for_aikido_zen, :join

          sink_before :open do |path|
            Helpers.scan(path, "open")
          end

          sink_before :read do |path|
            Helpers.scan(path, "read")
          end

          sink_before :write do |path|
            Helpers.scan(path, "write")
          end

          sink_before :truncate do |file_name|
            Helpers.scan(file_name, "truncate")
          end

          sink_before :rename do |old_name, new_name|
            Helpers.scan(old_name, "rename")
            Helpers.scan(new_name, "rename")
          end

          sink_before :unlink do |*file_names|
            file_names.each do |file_name|
              Helpers.scan(file_name, "unlink")
            end
          end

          sink_before :delete do |*file_names|
            file_names.each do |file_name|
              Helpers.scan(file_name, "delete")
            end
          end

          sink_before :symlink do |old_name, new_name|
            Helpers.scan(old_name, "symlink")
            Helpers.scan(new_name, "symlink")
          end

          sink_before :chmod do |_mode_int, *file_names|
            file_names.each do |file_name|
              Helpers.scan(file_name, "chmod")
            end
          end

          sink_before :chown do |_owner_int, group_int, *file_names|
            file_names.each do |file_name|
              Helpers.scan(file_name, "chown")
            end
          end

          sink_before :utime do |_atime, _mtime, *file_names|
            file_names.each do |file_name|
              Helpers.scan(file_name, "utime")
            end
          end

          def join(*args, **kwargs, &blk)
            # IMPORTANT: THE BEHAVIOR OF THIS METHOD IS CHANGED!
            #
            # File.join has undocumented behavior:
            #
            # File.join recursively joins nested string arrays.
            #
            # This prevents path traversal detection when an array originates
            # from user input that was assumed to be a string.
            #
            # This undocumented behavior has been restricted to support path
            # traversal detection.
            #
            # File.join no longer joins nested string arrays, but still accepts
            # a single string array argument.

            # File.join is often incorrectly called with a single array argument.
            #
            # i.e.
            #
            # File.join(["prefix", "filename"])
            #
            # This is considered acceptable.
            #
            # Calling File.join with a single string argument returns the string
            # argument itself, having no practical effect. Therefore, it can be
            # presumed that if File.join is called with a single array argument
            # then this was its intended usage, and the array did not originate
            # from user input that was assumed to be a string.
            strings = args
            strings = args.first if args.size == 1 && args.first.is_a?(Array)
            strings.each do |string|
              raise TypeError.new("Zen prevented implicit conversion of Array to String") if string.is_a?(Array)
            end

            result = join__internal_for_aikido_zen(*args, **kwargs, &blk)
            Sinks::DSL.safe do
              Helpers.scan(result, "join")
            end
            result
          end

          sink_before :expand_path do |file_name|
            Helpers.scan(file_name, "expand_path")
          end

          sink_before :realpath do |file_name|
            Helpers.scan(file_name, "realpath")
          end

          sink_before :realdirpath do |file_name|
            Helpers.scan(file_name, "realdirpath")
          end
        end

        ::File.class_eval do
          extend Sinks::DSL

          sink_before :initialize do |path|
            Helpers.scan(path, "new")
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::File.load_sinks!
