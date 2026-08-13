# frozen_string_literal: true

module Aikido::Zen
  module Sinks
    module IO
      SINK = Sinks.add("IO", scanners: [Scanners::PathTraversalScanner])

      module Helpers
        def self.scan(filepath, operation)
          SINK.scan(
            filepath: filepath,
            operation: operation
          )
        end
      end

      def self.load_sinks!
        ::IO.singleton_class.class_eval do
          extend Sinks::DSL

          sink_before :read do |path, *|
            Helpers.scan(path, "read")
          end

          sink_before :write do |path, *|
            Helpers.scan(path, "write")
          end

          sink_before :foreach do |path, *|
            Helpers.scan(path, "foreach")
          end

          sink_before :readlines do |path, *|
            Helpers.scan(path, "readlines")
          end

          sink_before :binread do |path, *|
            Helpers.scan(path, "binread")
          end

          sink_before :binwrite do |path, *|
            Helpers.scan(path, "binwrite")
          end
        end
      end
    end
  end
end

Aikido::Zen::Sinks::IO.load_sinks!
