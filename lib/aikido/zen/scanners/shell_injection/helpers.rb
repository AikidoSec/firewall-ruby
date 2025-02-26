# frozen_string_literal: true

module Aikido::Zen::Scanners::ShellInjectionScanner
  module Helpers
    ESCAPE_CHARS = %W[' "]
    DANGEROUS_CHARS_INSIDE_DOUBLE_QUOTES = %W[$ ` \\ !]
    DANGEROUS_CHARS = [
      "#", "!", '"', "$", "&", "'", "(", ")", "*", ";", "<", "=", ">", "?",
      "[", "\\", "]", "^", "`", "{", "|", "}", " ", "\n", "\t", "~"
    ]

    COMMANDS = %w[sleep shutdown reboot poweroff halt ifconfig chmod chown ping
      ssh scp curl wget telnet kill killall rm mv cp touch echo cat head
      tail grep find awk sed sort uniq wc ls env ps who whoami id w df du
      pwd uname hostname netstat passwd arch printenv logname pstree hostnamectl
      set lsattr killall5 dmesg history free uptime finger top shopt :]

    PATH_PREFIXES = %w[/bin/ /sbin/ /usr/bin/ /usr/sbin/ /usr/local/bin/ /usr/local/sbin/]

    SEPARATORS = [" ", "\t", "\n", ";", "&", "|", "(", ")", "<", ">"]

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

    # Helper function for sorting commands by length (longer commands first)
    def self.by_length(a, b)
      b.length - a.length
    end

    # Escape characters with special meaning either inside or outside character sets.
    # Use a simple backslash escape when it’s always valid, and a `\xnn` escape when the simpler
    # form would be disallowed by Unicode patterns’ stricter grammar.
    #
    # Inspired by https://github.com/sindresorhus/escape-string-regexp/
    def self.escape_string_regexp(string)
      string.gsub(/[|\\{}()\[\]^$+*?.]/) { "\\#{$&}" }.gsub("-", '\\x2d')
    end

    # Construct the regex for commands
    COMMANDS_REGEX = Regexp.new(
      "([/.]*((#{PATH_PREFIXES.map { |p| Helpers.escape_string_regexp(p) }.join("|")})?((#{COMMANDS.sort(&method(:by_length)).join("|")}))))",
      Regexp::IGNORECASE
    )

    def self.contains_shell_syntax(command, user_input)
      # Check if input is only whitespace
      return false if user_input.strip.empty?

      # Check if the user input contains any dangerous characters
      if DANGEROUS_CHARS.any? { |c| user_input.include?(c) }
        return true
      end

      # If the command is exactly the same as the user input, check if it matches the regex
      if command == user_input
        return match_all(command, COMMANDS_REGEX).any? do |match|
          match[0].length == command.length && match[0] == command
        end
      end

      # Check if the command contains a commonly used command
      match_all(command, COMMANDS_REGEX).each do |match|
        next if user_input != match[0]

        # Check if the command is surrounded by separators
        char_before = command[match[1] - 1]
        char_after = command[match[1] + match[0].length]

        if SEPARATORS.include?(char_before) && SEPARATORS.include?(char_after)
          return true
        end

        if SEPARATORS.include?(char_before) && char_after.nil?
          return true
        end

        if char_before.nil? && SEPARATORS.include?(char_after)
          return true
        end
      end

      false
    end

    def self.match_all(string, regex)
      string.enum_for(:scan, regex).map do |match|
        [match[0], $~.begin(0)]
      end
    end
  end
end
