# Changelog

## [Unreleased]

### Fixed

- Avoid an error when sending the initial heartbeat if the Aikido server hasn't
  received stats yet.
- Fix the SSRF scanner to ensure the port in the user-supplied payload matches
  the port in the request.

## 0.1.0

- Initial version
