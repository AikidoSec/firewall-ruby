# frozen_string_literal: true

module Aikido::Zen::Scanners::ShellInjection
  module Helpers
    ESCAPE_CHARS = %W[' "]
    DANGEROUS_CHARS_INSIDE_DOUBLE_QUOTES = %W[$ ` \\ !]
    DANGEROUS_CHARS = [
      "#", "!", '"', "$", "&", "'", "(", ")", "*", ";", "<", "=", ">", "?",
      "[", "\\", "]", "^", "`", "{", "|", "}", " ", "\n", "\t", "~", "\r", "\f"
    ]

    COMMANDS = %w[sleep shutdown reboot poweroff halt ifconfig chmod chown ping
      ssh scp curl wget telnet kill killall rm mv cp touch echo cat head
      tail grep find awk sed sort uniq wc ls env ps who whoami id w df du
      pwd uname hostname netstat passwd arch printenv logname pstree hostnamectl
      set lsattr killall5 dmesg history free uptime finger top shopt :]

    PATH_PREFIXES = %w[/bin/ /sbin/ /usr/bin/ /usr/sbin/ /usr/local/bin/ /usr/local/sbin/]

    SEPARATORS = [" ", "\t", "\n", ";", "&", "|", "(", ")", "<", ">", "\r", "\f"]

    # @param command [string]
    # @param user_input [string]
    def self.is_safely_encapsulated(command, user_input)
      segments = command.split(user_input)

      # The next condition is merely here to be compliant with what javascript does when splitting strings:
      # From js doc https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/split
      #   > If separator appears at the beginning (or end) of the string, it still has the effect of splitting,
      #   > resulting in an empty (i.e. zero length) string appearing at the first (or last) position of
      #   > the returned array.
      # This is necessary because this code is ported form the firewall-node code.
      if user_input.length > 1
        if command.start_with? user_input
          segments.unshift ""
        end

        if command.end_with? user_input
          segments << ""
        end
      end

      # Call the helper function to get current and next segments
      get_current_and_next_segments(segments).all? do |segments_pair|
        char_before_user_input = segments_pair[:current_segment][-1]
        char_after_user_input = segments_pair[:next_segment][0]

        # Check if the character before is an escape character
        is_escape_char = ESCAPE_CHARS.include?(char_before_user_input)

        unless is_escape_char
          next false
        end

        # If characters before and after the user input do not match, return false
        next false if char_before_user_input != char_after_user_input

        # If user input contains the escape character, return false
        next false if user_input.include?(char_before_user_input)

        # Handle dangerous characters inside double quotes
        if char_before_user_input == '"' && DANGEROUS_CHARS_INSIDE_DOUBLE_QUOTES.any? { |char| user_input.include?(char) }
          next false
        end

        next true
      end
    end

    def self.get_current_and_next_segments(segments)
      segments.each_cons(2).map { |current_segment, next_segment| {current_segment: current_segment, next_segment: next_segment} }
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
          match[:match].length == command.length && match[:match] == command
        end
      end

      # Check if the command contains a commonly used command
      match_all(command, COMMANDS_REGEX).each do |match|
        # We found a command like `rm` or `/sbin/shutdown` in the command
        # Check if the command is the same as the user input
        # If it's not the same, continue searching
        next if user_input != match[:match]

        # Otherwise, we'll check if the command is surrounded by separators
        # These separators are used to separate commands and arguments
        # e.g. `rm<space>-rf`
        # e.g. `ls<newline>whoami`
        # e.g. `echo<tab>hello` Check if the command is surrounded by separators
        char_before = if match[:index] - 1 < 0
          nil
        else
          command[match[:index] - 1]
        end

        char_after = if match[:index] + match[:match].length >= command.length
          nil
        else
          command[match[:index] + match[:match].length]
        end

        # e.g. `<separator>rm<separator>`
        if SEPARATORS.include?(char_before) && SEPARATORS.include?(char_after)
          return true
        end

        # e.g. `<separator>rm`
        if SEPARATORS.include?(char_before) && char_after.nil?
          return true
        end

        # e.g. `rm<separator>`
        if char_before.nil? && SEPARATORS.include?(char_after)
          return true
        end
      end

      false
    end

    def self.match_all(string, regex)
      string.enum_for(:scan, regex).map do |match|
        {match: match[0], index: $~.begin(0)}
      end
    end
  end
end
