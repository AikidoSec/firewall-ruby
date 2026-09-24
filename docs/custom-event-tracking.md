# Track custom events

Use `Aikido::Zen.track` to report events that only your application knows about, such as failed logins. [Playbooks](https://help.aikido.dev/zen-firewall/zen-features/playbooks) can act when an event occurs repeatedly, for example by blocking an IP after three failed logins in five minutes.

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  private

  def authenticate_user!
    # Your authentication logic here
    # ...

    unless current_user
        Aikido::Zen.track("user.login_failed")
        return
    end

    Aikido::Zen.set_user(
      id: current_user.id,
      name: current_user.name
    )

    Aikido::Zen.track("user.login_succeeded")
  end
end
```

After adding `Aikido::Zen.track`, trigger the event at least once. It will then appear on the Playbooks page in the Aikido dashboard. From there, you can create a playbook and choose what should happen when the event occurs. Calling `Aikido::Zen.track` by itself does not create a playbook or block anything.

Call `Aikido::Zen.track` while handling an HTTP request. Zen associates the event with the request's IP address. Playbook counts are per IP, not across your whole app. If you call [`Aikido::Zen.set_user`](./rails.md#rate-limiting-and-user-blocking) before tracking the event, Zen also includes the current user. `Aikido::Zen.set_user` is optional. Events without a user are still tracked.

Event names can use any format. We recommend lowercase, dot-separated names such as `user.login_failed`.
