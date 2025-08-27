# Setting up Zen on a Ruby on Rails application

To install Zen, add the gem:

```sh
bundle add aikido-zen
```

And require it before `Bundler.require` in `config/application.rb`:

```ruby
# config/application.rb
require_relative "boot"

require "rails/all"

require "aikido-zen"
Aikido::Zen.protect!

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

...
```

That's it! Zen will start to run inside your app when it starts getting
requests.

## Rate limiting and user blocking

If you want to add the rate limiting feature to your app, modify your code like this:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  private

  def current_user
    return unless session[:user_id]
    User.find(session[:user_id])
  end

  def authenticate_user!
    # Your authentication logic here
    # ...
    # Optional, if you want to use user based rate limiting or block specific users
    Aikido::Zen.set_user(
      id: current_user.id,
      name: current_user.name
    )
  end
end
```

## Configuration

Zen exposes its configuration object to the Rails configuration, which you can
modify in an initializer if desired:

```ruby
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

```yaml
# config/credentials.yml.enc
zen:
  token: "AIKIDO_RUNTIME_..."
```

You can just tell Zen to use it like so:

```ruby
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

```ruby
# config/initializers/zen.rb
Rails.application.config.zen.logger = Logger.new(...)
```

You should supply an instance of ruby's [Logger](https://github.com/ruby/logger)
class.
