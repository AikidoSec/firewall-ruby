# frozen_string_literal: true

module Aikido::Zen
  # Hooked only on `read` & `write` methods of `File`. We could extends to other methods like `open`
  # but that's outside of the challenge scope.
  module Sinks
    module File
      SINK = Sinks.add("File", scanners: [
        Aikido::Zen::Scanners::PathTraversalScanner
      ])

      module Extensions
        def self.scan_path(filepath, operation)
          Aikido::Zen.config.logger.debug "Sending to scan: #{filepath}"

          SINK.scan(
            filepath: filepath,
            operation: operation
          )
        end

        module InstanceMethods
          def initialize(filename, *, **)
            Extensions.scan_path(filename, "new")
            super
          end
        end

        module ClassMethods
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

          def chmod(mode, path)
            Extensions.scan_path(path, "chmod")
            super
          end

          def chown(user, group, path)
            Extensions.scan_path(path, "chown")
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
        end
      end
    end
  end
end

::File.singleton_class.prepend(Aikido::Zen::Sinks::File::Extensions::ClassMethods)
::File.prepend Aikido::Zen::Sinks::File::Extensions::InstanceMethods
