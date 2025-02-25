# frozen_string_literal: true

module Aikido::Zen::Scanners::ShellInjectionScanner
  module Helpers
    ESCAPE_CHARS = %W[' "]
    DANGEROUS_CHARS_INSIDE_DOUBLE_QUOTES = %W[$ ` \\ !]

    def self.is_safely_encapsulated(command, user_input)
      command.split(user_input).each_cons(2) do |first_segment, second_segment|
        char_before_input = first_segment[-1]
        char_after_input = second_segment[0, 1]

        is_escape_char = ESCAPE_CHARS.find { |char| char == char_before_input }

        return false unless is_escape_char

        return false if char_before_input != char_after_input

        return false if user_input.include?(char_before_input)

        # There are no dangerous characters inside single quotes
        # You can use certain characters inside double quotes
        # https://www.gnu.org/software/bash/manual/html_node/Single-Quotes.html
        # https://www.gnu.org/software/bash/manual/html_node/Double-Quotes.html
        return false if is_escape_char == '"' &&
          DANGEROUS_CHARS_INSIDE_DOUBLE_QUOTES.any? { |char| user_input.include?(char) }

        return true
      end
    end

    def self.contains_shell_syntax(command, input)
      # code here
    end

    # Escape characters with special meaning either inside or outside character sets.
    # Use a simple backslash escape when it’s always valid, and a `\xnn` escape when the simpler
    # form would be disallowed by Unicode patterns’ stricter grammar.
    #
    # Inspired by https://github.com/sindresorhus/escape-string-regexp/
    def self.escape_string_regexp(string)
      string.gsub(/[|\\{}()\[\]^$+*?.]/) { "\\#{$&}" }.gsub("-", '\\x2d')
    end
  end
end
