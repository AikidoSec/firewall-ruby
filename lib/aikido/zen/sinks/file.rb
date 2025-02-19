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

        def read(filename, *)
          Extensions.scan_path(filename, "read")
          super
        end

        def write(filename, *, **)
          Extensions.scan_path(filename, "write")
          super
        end

        def join(path, *args)
          joined = super
          Extensions.scan_path(joined, "join")
          joined
        end
      end
    end
  end
end

::File.singleton_class.prepend(Aikido::Zen::Sinks::File::Extensions)
