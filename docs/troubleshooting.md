# Troubleshooting

If the Zen Firewall isn't working as expected, follow these steps in order to diagnose common issues.

## Review installation steps

Double-check your setup against the [installation guide](../README.md#installation).

Make sure:
- Your runtime and framework are supported (see [Supported libraries and frameworks](../README.md#supported-libraries-and-frameworks)).
- The package installed successfully.
- The firewall is initialized early in your app.
- Your framework-specific integration matches the example in the README.

## Check connection to Aikido

The firewall must be able to reach Aikido's API endpoints.

Test connectivity from the same environment where your app runs, following the instructions on this page: https://help.aikido.dev/zen-firewall/miscellaneous/outbound-network-connections-for-zen

## Check logs for errors

Common places:
- Local dev: `cat log/development.log` or `tail -f log/development.log`
- Docker: `docker logs <your-app-container>`
- systemd: `journalctl -u <your-app-service> --since "1 hour ago"`

Tip: search logs for lines containing `Aikido` or `Zen`.

For example:

```sh
grep -Ei 'aikido|zen' log/development.log
```

## Enable debug output temporarily

If you use Rails, set the log level to `info` or `debug` while you investigate.

```ruby
# config/environments/development.rb or production.rb
config.log_level = :info # use :debug if needed
```

If you have your own logger, make sure Zen logs go to stdout.

You can enable Zen debugging mode as follows.

```ruby
# config/initializers/zen.rb
Rails.application.config.zen.debugging = true
```

Or set `AIKIDO_DEBUG=true` in your environment.

## Contact support

If you still can't resolve the problem:

- Use the in-app chat to reach our support team directly.
- Or create an issue on [GitHub](https://github.com/AikidoSec/firewall-ruby/issues) with details about your setup, framework, and logs.

Include as much context as possible; this helps us respond faster.
