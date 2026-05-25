# Tracking events

`Aikido::Zen.track_user_event` lets you record things happening in your app — like failed logins, signups, or password resets. Zen sends these to Aikido so patterns can be detected, like someone failing to log in 50 times in a minute.

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  private

  def authenticate_user!
    # Your authentication logic here
    # ...

    unless current_user
        Aikido::Zen.track_user_event("user.login_failed")
        return
    end

    Aikido::Zen.set_user(
      id: current_user.id,
      name: current_user.name
    )

    Aikido::Zen.track_user_event("user.login_succeeded")
  end
end
```

Zen automatically picks up the IP address, user agent, and current user (if you called [`setUser`](./user.md)) from the request — you don't need to pass those yourself.

## More examples

```ruby
Aikido::Zen.track_user_event("user.signed_up")
Aikido::Zen.track_user_event("user.password_reset_requested")
Aikido::Zen.track_user_event("plan.invite_sent")
Aikido::Zen.track_user_event("payment.failed")
```

## Naming events

Use lowercase with dots to group related events:

- `user.login_failed`
- `user.login_succeeded`
- `user.signed_up`
- `user.password_reset_requested`
- `payment.failed`
- `plan.invite_sent`

## Things to know

`Aikido::Zen.track_user_event` only works inside an HTTP request. If you call it in a background job or a script, nothing gets sent and you'll see a warning in the console.

If you haven't called `Aikido::Zen.set_user` yet, the event still goes through — it just won't have a user ID attached.
