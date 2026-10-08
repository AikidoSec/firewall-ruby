# frozen_string_literal: true

module Aikido::Zen
  module Scanners
    module PathTraversal
      DANGEROUS_PATH_PARTS = ["../", "..\\"]

      LINUX_PATH_STARTS = [
        "/bin/",
        "/boot/",
        "/dev/",
        "/etc/",
        "/home/",
        "/init/",
        "/lib/",
        "/media/",
        "/mnt/",
        "/opt/",
        "/proc/",
        "/root/",
        "/run/",
        "/sbin/",
        "/srv/",
        "/sys/",
        "/tmp/",
        "/usr/",
        "/var/",
        # Common container/cloud directories
        "/app/",
        "/code/",
        "/data/",
        "/rails/",
        "/workspace/",
        "/workspaces/"
      ]

      MACOS_PATH_STARTS = [
        "/applications/",
        "/cores/",
        "/library/",
        "/private/",
        "/users/",
        "/system/",
        "/volumes/"
      ]

      WINDOWS_PATH_STARTS = ["c:/", "c:\\"]

      DANGEROUS_PATH_STARTS = LINUX_PATH_STARTS + MACOS_PATH_STARTS + WINDOWS_PATH_STARTS

      module Helpers
        def self.include_unsafe_path_parts?(filepath)
          DANGEROUS_PATH_PARTS.each do |dangerous_part|
            return true if filepath.include?(dangerous_part)
          end

          false
        end

        def self.start_with_unsafe_path?(filepath, user_input)
          # If the filepath itself is relative, we cannot check for absolute dangerous paths
          return false if Pathname.new(filepath).relative?

          # Normalize the filepath
          normalized_path = File.expand_path__internal_for_aikido_zen(filepath).downcase.squeeze("/")
          
          # For user_input, we need to handle both absolute and relative cases
          # If user_input is relative (e.g., "etc/passwd"), it might resolve to an absolute
          # dangerous path (e.g., "/etc/passwd") depending on the expansion context.
          # We check both the user_input as-is and with a leading "/" prepended.
          user_input_is_relative = Pathname.new(user_input).relative?
          
          normalized_user_input = File.expand_path__internal_for_aikido_zen(user_input).downcase.squeeze("/")
          
          # If user_input is relative, also check if prepending "/" would match the filepath
          # This catches cases like user_input="etc/passwd" matching filepath="/etc/passwd"
          normalized_user_input_with_slash = nil
          if user_input_is_relative
            # Prepend "/" and normalize to check if the relative path matches an absolute dangerous path
            user_input_with_slash = "/#{user_input}"
            normalized_user_input_with_slash = File.expand_path__internal_for_aikido_zen(user_input_with_slash).downcase.squeeze("/")
          end

          DANGEROUS_PATH_STARTS.each do |dangerous_start|
            # Check with the original normalized user_input
            if normalized_path.start_with?(dangerous_start) && normalized_path.start_with?(normalized_user_input)
              # If the user input is the same as the dangerous start, we don't want to flag it
              # to prevent false positives.
              # e.g., if user input is /etc/ and the path is /etc/passwd, we don't want to flag it,
              # as long as the user input does not contain a subdirectory or filename
              return false if user_input == dangerous_start || user_input == dangerous_start.chomp("/")

              return true
            end
            
            # If user_input was relative, also check with "/" prepended
            if normalized_user_input_with_slash && 
               normalized_path.start_with?(dangerous_start) && 
               normalized_path.start_with?(normalized_user_input_with_slash)
              # Apply the same false positive prevention check
              return false if user_input_with_slash == dangerous_start || user_input_with_slash == dangerous_start.chomp("/")
              
              return true
            end
          end

          false
        end
      end
    end
  end
end
