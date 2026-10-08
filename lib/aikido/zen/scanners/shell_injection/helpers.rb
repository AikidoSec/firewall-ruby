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
      # Return false if user input is not in the command
      return true unless command.include?(user_input)

      # Find all occurrences of user_input in command
      occurrences = []
      start_pos = 0
      while (pos = command.index(user_input, start_pos))
        occurrences << pos
        start_pos = pos + 1
      end

      # Check if all occurrences are safely encapsulated
      occurrences.all? do |occurrence_index|
        is_occurrence_safely_encapsulated(command, user_input, occurrence_index)
      end
    end

    # Check if a specific occurrence of user_input in command is safely encapsulated
    # by parsing shell quote state from the beginning of the command
    def self.is_occurrence_safely_encapsulated(command, user_input, occurrence_index)
      quote_state = nil  # nil = unquoted, "'" = single-quoted, '"' = double-quoted
      i = 0
      
      while i < occurrence_index
        char = command[i]
        
        if quote_state.nil?
          # We're in unquoted context
          if char == '\\'
            # Backslash escapes the next character in unquoted context
            i += 1
          elsif char == "'"
            quote_state = "'"
          elsif char == '"'
            quote_state = '"'
          end
        elsif quote_state == "'"
          # We're in single-quoted context
          # In single quotes, nothing is special except the closing single quote
          if char == "'"
            quote_state = nil
          end
        elsif quote_state == '"'
          # We're in double-quoted context
          if char == '\\'
            # Skip the next character (it's escaped)
            i += 1
          elsif char == '"'
            quote_state = nil
          end
        end
        
        i += 1
      end

      # Now check the quote state at the start of user_input
      start_quote_state = quote_state

      # Parse through the user_input to see what the quote state would be at the end
      user_input.each_char do |char|
        if quote_state.nil?
          # If we start unquoted, user input is not safely encapsulated
          return false
        elsif quote_state == "'"
          # In single quotes, check if user input contains a single quote
          if char == "'"
            # User input contains the quote character that would close the encapsulation
            return false
          end
        elsif quote_state == '"'
          # In double quotes, check for dangerous characters
          if char == '"'
            # User input contains the quote character that would close the encapsulation
            return false
          elsif char == '\\'
            # Backslash in double quotes is dangerous
            return false
          elsif DANGEROUS_CHARS_INSIDE_DOUBLE_QUOTES.any? { |dangerous| char == dangerous }
            return false
          end
        end
      end

      # Verify that after the user_input, we're still in the same quote state
      # by checking the character immediately after
      end_index = occurrence_index + user_input.length
      if end_index < command.length
        # Continue parsing to verify the quote is properly closed
        char_after = command[end_index]
        
        if quote_state == "'" && char_after == "'"
          # Good: single quote is closed
          return true
        elsif quote_state == '"' && char_after == '"'
          # Good: double quote is closed
          return true
        else
          # The quote is not properly closed immediately after
          return false
        end
      else
        # User input is at the end of command, not properly closed
        return false
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
