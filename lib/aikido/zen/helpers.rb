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

      # Returns a copy of the regexp with the timeout set if timeout is supported.
      #
      # @param regexp [Regexp] the regexp
      # @return [Regexp] the regexp with timeout set
      def self.regexp_with_timeout(regexp, timeout: Aikido::Zen.config.redos_regexp_timeout)
        return regexp if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")

        Regexp.new(regexp.source, regexp.options, timeout: timeout)
      end

      # Returns a copy of the string safely encoded as UTF-8.
      #
      # Web servers may deliver request data as binary strings. These strings
      # are relabeled as UTF-8 instead of being converted, because conversion
      # would replace every non-ASCII byte with U+FFFD, even in valid UTF-8.
      #
      # @param string [String] the string
      # @return [String] the valid UTF-8 string
      def self.encode_safely(string)
        if string.encoding == Encoding::BINARY
          string.dup.force_encoding(Encoding::UTF_8).scrub
        else
          string.encode("UTF-8", invalid: :replace, undef: :replace)
        end
      end
    end
  end
end
