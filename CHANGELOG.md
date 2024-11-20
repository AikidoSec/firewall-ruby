# Changelog

## [Unreleased]

### Fixed

- Avoid an infinite loop when checking for SSRFs in a circular redirects loop.

## 0.1.1

### Fixed

- Avoid an error when sending the initial heartbeat if the Aikido server hasn't
  received stats yet.
- Fix the SSRF scanner to ensure the port in the user-supplied payload matches
  the port in the request.
- Don't break the HTTP.rb sink when a Zen context isn't set.
- Don't break the Typhoeus sink when a Zen context isn't set.
- Don't break the PG sink outside of Rails.
- Updated [libzen](https://github.com/AikidoSec/zen-internals) to v0.1.31 to
  prevent flagging false positives in SQL queries with comments.

## 0.1.0

- Initial version
