# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module File
      def self.load_sinks!
        # Create a copy of the original method for internal use only to prevent
        # recursion in PathTraversalScanner.
        #
        # IMPORTANT: The alias must be created before the method is overridden,
        # when the extensions are prepended.
        ::File.singleton_class.alias_method(:expand_path__internal_for_aikido_zen, :expand_path)

        ::File.singleton_class.prepend(FileClassExtensions)
        ::File.prepend(FileExtensions)
      end

      SINK = Sinks.add("File", scanners: [Scanners::PathTraversalScanner])

      module Helpers
        def self.scan(filepath, operation)
          SINK.scan(
            filepath: filepath,
            operation: operation
          )
        end
      end

      module FileClassExtensions
        extend Sinks::DSL

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

        sink_after :join do |result|
          Helpers.scan(result, "join")
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

      module FileExtensions
        extend Sinks::DSL

        sink_before :initialize do |path|
          Helpers.scan(path, "new")
        end
      end
    end
  end
end

Aikido::Zen::Sinks::File.load_sinks!
