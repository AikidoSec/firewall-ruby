# frozen_string_literal: true

require "pathname"

module Aikido::Zen
  module Sinks
    module Pathname
      SINK = Sinks.add("Pathname", scanners: [Scanners::PathTraversalScanner])

      module Helpers
        def self.scan(filepath, operation)
          SINK.scan(
            filepath: filepath,
            operation: operation
          )
        end
      end

      def self.load_sinks!
        ::Pathname.class_eval do
          extend Sinks::DSL

          sink_before :cleanpath do
            Aikido::Zen::Sinks::Pathname::Helpers.scan(to_s, "cleanpath")
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::Pathname.load_sinks!
