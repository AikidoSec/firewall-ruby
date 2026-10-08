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
          # Check if path is relative (not absolute or drive letter path)
          # Required because `expand_path` will build absolute paths from relative paths
          return false if Pathname.new(filepath).relative? || Pathname.new(user_input).relative?

          normalized_path = File.expand_path__internal_for_aikido_zen(filepath).downcase.squeeze("/")
          normalized_user_input = File.expand_path__internal_for_aikido_zen(user_input).downcase.squeeze("/")

          # Check if the normalized path starts with the normalized user input
          # This catches absolute path traversal attacks regardless of the specific directory
          if normalized_path.start_with?(normalized_user_input)
            # Check if user input is a bare root directory to prevent false positives
            # e.g., if user input is /etc/ and the path is /etc/passwd, we don't want to flag it
            DANGEROUS_PATH_STARTS.each do |dangerous_start|
              if normalized_user_input == dangerous_start.downcase || normalized_user_input == dangerous_start.downcase.chomp("/")
                return false
              end
            end

            # If the user input specifies more than just a root directory, it's an attack
            # This catches cases like /secret/file, /custom/path, etc.
            return true
          end

          false
        end
      end
    end
  end
end
