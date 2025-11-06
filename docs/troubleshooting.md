# Troubleshooting

## Review installation steps

Double-check your setup against the [installation guide](../README.md#installation).
Make sure:
- The package installed correctly.
- The firewall is initialized early in your app (before routes or handlers).
- Your framework-specific integration (middleware, decorator, etc.) matches the example in the README.
- You’re running a supported runtime version for your language.

## Check connection to Aikido

The firewall must be able to reach Aikido’s API endpoints.

Test from the same environment where your app runs and follow the instructions on this page: https://help.aikido.dev/zen-firewall/miscellaneous/outbound-network-connections-for-zen

## Check logs for errors

Common places:
- Docker: `docker logs <your-app-container>`
- systemd: `journalctl -u <your-app-service> --since "1 hour ago"`
- Local dev: your terminal or IDE run console

Tip: search for lines that contain `Aikido` or `AikidoZen`.

## Enable debug logs temporarily
If you use Rails, set the log level to `info` or `debug` while you investigate.

```ruby
# config/environments/development.rb or production.rb
config.log_level = :info # use :debug if needed
```

If you have your own logger, make sure AikidoZen logs go to stdout.

## Confirm the gem is installed

```
bundle list | grep -i aikido
gem list | grep -i aikido
```

## Confirm it is wired early in the Rack stack
The firewall must see every request before your routes or other middleware.

Rails

Add the middleware near the top of the stack.

```
# config/application.rb
config.middleware.insert_before 0, AikidoZen::Middleware
```

You can also keep this in an initializer:

```
# config/initializers/aikido_zen.rb
Rails.application.config.middleware.insert_before 0, AikidoZen::Middleware
```

Check the stack order: `rails middleware`

Sinatra or pure Rack

Use the middleware in config.ru before routes are mounted.

```
# config.ru
require "aikido_zen"
use AikidoZen::Middleware
run MyApp

```

If your integration uses an explicit call

Some setups expose a helper to wrap the app.

```
# config.ru
require "aikido_zen"
run AikidoZen.protect(MyApp)
```

## Contact support

If you still can’t resolve the issue:

- Use the in-app chat to reach our support team directly.
- Or create an issue on [GitHub](../../issues) with details about your setup, framework, and logs.

Include as much context as possible (framework, logs, and how Aikido was added) so we can help you quickly.
