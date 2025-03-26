# Setting up Zen on a Ruby on Rails application

## Installation

1. Add the Aikido Zen gem:

```
bundle add aikido-zen
```

2. Set your Aikido token as an environment variable:
```sh
AIKIDO_TOKEN="AIK_RUNTIME_YOUR_TOKEN_HERE"
```

You can get your token from the [Aikido Security Dashboard](https://help.aikido.dev/doc/creating-an-aikido-zen-firewall-token/doc6vRJNzC4u).

That's it! Zen will start to run inside your app when it starts getting
requests.

## Configuration

Zen exposes its configuration object to the Rails configuration, which you can
modify in an initializer if desired:

``` ruby
# config/initializers/zen.rb
Rails.application.config.zen.api_timeouts = 20
```

You can access the configuration object both as `Aikido::Zen.config` or
`Rails.configuration.zen`.

See our [configuration guide](docs/config.md) for more details.

## Using Rails encrypted credentials

If you're using Rails' [encrypted credentials][creds], and prefer not storing
sensitive values in your env vars, you can easily configure Zen for it. For
example, assuming the following credentials structure:

``` yaml
# config/credentials.yml.enc
zen:
  token: "AIKIDO_RUNTIME_..."
```

You can just tell Zen to use it like so:

``` ruby
# config/initializers/zen.rb
Rails.application.config.zen.token = Rails.application.credentials.zen.token
```

[creds]: https://guides.rubyonrails.org/security.html#environmental-security

## Blocking mode

By default, Zen will only detect and log attacks, but will not block them. You
can enable blocking mode by setting the `AIKIDO_BLOCK` environment variable
to `true`.

When in blocking mode, Zen will raise an exception when it detects an attack.
These exceptions depend on the type of attack, but all inherit from
`Aikido::Zen::UnderAttackError`, if you wish to handle these exceptions in any
way.

## Logging

By default, Zen will use the Rails logger, prefixing messages with `[aikido]`.
You can redirect the log to a separate stream by overriding the logger:

```
# config/initializers/zen.rb
Rails.application.config.zen.logger = Logger.new(...)
```

You should supply an instance of ruby's [Logger](https://github.com/ruby/logger)
class.
