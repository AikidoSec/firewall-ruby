# frozen_string_literal: true

# Trusted SHA-256 checksums for libzen native artifacts.
# These checksums are version-controlled and provide an independent trust anchor
# for verifying downloaded artifacts from GitHub releases.
#
# When updating LIBZEN_VERSION in lib/aikido/zen/version.rb, these checksums
# must be updated to match the new release artifacts.
#
# To obtain checksums for a new version:
# 1. Manually download artifacts from the GitHub release
# 2. Compute SHA-256 for each: shasum -a 256 <artifact>
# 3. Update the CHECKSUMS hash below
# 4. Commit the changes to version control
#
# SECURITY: Never fetch checksums programmatically from the same source as the
# artifacts. The checksums in this file serve as an independent trust anchor.
module LibZenChecksums
  # Checksums for libzen v0.1.74
  # TODO: Replace these placeholder values with actual checksums from a trusted source
  # The current values are SHA-256 of an empty string and must be updated before use.
  CHECKSUMS = {
    "libzen_internals_aarch64-apple-darwin.dylib" => "PLACEHOLDER_UPDATE_REQUIRED",
    "libzen_internals_aarch64-unknown-linux-gnu.so" => "PLACEHOLDER_UPDATE_REQUIRED",
    "libzen_internals_aarch64-unknown-linux-musl.so" => "PLACEHOLDER_UPDATE_REQUIRED",
    "libzen_internals_x86_64-apple-darwin.dylib" => "PLACEHOLDER_UPDATE_REQUIRED",
    "libzen_internals_x86_64-unknown-linux-gnu.so" => "PLACEHOLDER_UPDATE_REQUIRED",
    "libzen_internals_x86_64-unknown-linux-musl.so" => "PLACEHOLDER_UPDATE_REQUIRED",
    "libzen_internals_x86_64-pc-windows-gnu.dll" => "PLACEHOLDER_UPDATE_REQUIRED"
  }.freeze

  def self.get(artifact_name)
    CHECKSUMS[artifact_name]
  end
end
