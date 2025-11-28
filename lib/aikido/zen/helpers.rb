# frozen_string_literal: true

module Aikido
  module Zen
    # @api private
    module Helpers
      # Normalizes a path by:
      #
      #   1. Collapsing consecutive forward slashes into a single forward slash.
      #   2. Removing forward trailing slash, unless the normalized path is "/".
      #
      # @param path [String, nil] the path to normalize.
      # @return [String, nil] the normalized path.
      def self.normalize_path(path)
        return path unless path

        normalized_path = path.dup
        normalized_path.squeeze!("/")
        normalized_path.chomp!("/") unless normalized_path == "/"
        normalized_path
      end
    end
  end
end
