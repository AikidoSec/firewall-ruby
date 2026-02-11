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
        "/code/"
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

          normalized_path = File.expand_path__internal_for_aikido_zen(filepath).downcase
          normalized_user_input = File.expand_path__internal_for_aikido_zen(user_input).downcase

          DANGEROUS_PATH_STARTS.each do |dangerous_start|
            if normalized_path.start_with?(dangerous_start) && normalized_path.start_with?(normalized_user_input)
              # If the user input is the same as the dangerous start, we don't want to flag it
              # to prevent false positives.
              # e.g., if user input is /etc/ and the path is /etc/passwd, we don't want to flag it,
              # as long as the user input does not contain a subdirectory or filename
              return false if user_input == dangerous_start || user_input == dangerous_start.chomp("/")

              return true
            end
          end

          false
        end
      end
    end
  end
end
