# Changelog

## [1.0.2.beta.5] - 2025-09-09

### Added

- Stored SSRF feature flag.

### Changed

- Aligned metadata with `firewall-node`, but reporting resolved IP as `resolvedIP`.

## [1.0.2.beta.4] - 2025-09-08

Attempted release, publishing failed.

## [1.0.2.beta.3] - 2025-09-08

Attempted release, publishing failed.

## [1.0.2.beta.2] - 2025-09-05

### Added

- Support for a custom client IP header via `AIKIDO_CLIENT_IP_HEADER` or `Aikido::Zen.config.client_ip_header`.

### Fixed

- Renamed `pathToPayload` to `path` in attack JSON and related tests.
