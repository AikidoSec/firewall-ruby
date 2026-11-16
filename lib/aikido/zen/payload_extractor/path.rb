# frozen_string_literal: true

module Aikido::Zen
  class PayloadExtractor
    class Path
      class Marker
        # @param name [String] the name of the marker in a path.
        def initialize(name)
          @name = name.freeze
        end

        # @return [String] the name of the marker in a path.
        def to_s
          @name
        end
      end

      JWT_MARKER = Marker.new("<jwt>")
      FILE_JOIN_MARKER = Marker.new("<File.join>")

      def initialize
        @segments = []
      end

      # @return [Integer] the number of segments in the path.
      def size
        @segments.size
      end

      # @param segment [Object] a key, an index or a {Marker}.
      # @return [void]
      def push(segment)
        @segments.push(segment)
      end

      # @return [void]
      def pop
        @segments.pop
      end

      # @return [String] the path to the payload, as a valid UTF-8 string.
      def to_s
        path = +""

        @segments.each_with_index do |segment, index|
          path << "." unless index.zero? || segment.is_a?(Marker)
          path << Helpers.encode_safely(segment.to_s)
        end

        path
      end
    end
  end
end
