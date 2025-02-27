# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module File
      SINK = Sinks.add("File", scanners: [
        Aikido::Zen::Scanners::PathTraversalScanner
      ])

      module Extensions
        def self.scan_path(filepath, operation)
          SINK.scan(
            filepath: filepath,
            operation: operation
          )
        end

        # Module to extend only the initializer method of `File` (`File.new`)
        module Initiliazer
          def initialize(filename, *, **)
            Extensions.scan_path(filename, "new")
            super
          end
        end

        def open(filename, *, **)
          Extensions.scan_path(filename, "open")
          super
        end

        def read(filename, *)
          Extensions.scan_path(filename, "read")
          super
        end

        def write(filename, *, **)
          Extensions.scan_path(filename, "write")
          super
        end

        def join(*)
          joined = super
          Extensions.scan_path(joined, "join")
          joined
        end

        def chmod(mode, *paths)
          paths.each { |path| Extensions.scan_path(path, "chmod") }
          super
        end

        def chown(user, group, *paths)
          paths.each { |path| Extensions.scan_path(path, "chown") }
          super
        end

        def rename(from, to)
          Extensions.scan_path(from, "rename")
          Extensions.scan_path(to, "rename")
          super
        end

        def symlink(from, to)
          Extensions.scan_path(from, "symlink")
          Extensions.scan_path(to, "symlink")
          super
        end

        def truncate(file_name, *)
          Extensions.scan_path(file_name, "truncate")
          super
        end

        def unlink(*args)
          args.each do |arg|
            Extensions.scan_path(arg, "unlink")
          end
          super
        end

        def delete(*args)
          args.each do |arg|
            Extensions.scan_path(arg, "delete")
          end
          super
        end

        def utime(atime, mtime, *args)
          args.each do |arg|
            Extensions.scan_path(arg, "utime")
          end
          super
        end

        def expand_path(filename, *)
          Extensions.scan_path(filename, "expand_path")
          super
        end

        def realpath(filename, *)
          Extensions.scan_path(filename, "realpath")
          super
        end

        def realdirpath(filename, *)
          Extensions.scan_path(filename, "realdirpath")
          super
        end
      end
    end
  end
end

# Internally, Path Traversal's scanner logic uses `expand_path`, in order to avoid recursion issues we keep
# a copy of the original method, only to be used internally.
# It's important to keep this line before prepend the Extensions module, otherwise the alias will call
# the extended method.
::File.singleton_class.alias_method :expand_path__internal_for_aikido_zen, :expand_path
::File.singleton_class.prepend(Aikido::Zen::Sinks::File::Extensions)
::File.prepend Aikido::Zen::Sinks::File::Extensions::Initiliazer
