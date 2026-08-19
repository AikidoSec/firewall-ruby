# Bypass Zen for a specific request

Call `Aikido::Zen.request_bypassed!` from a Rack middleware to bypass Zen for this request. A bypassed request is fully excluded from Zen inspection and enforcement: Zen will not analyze the request, generate findings, or apply blocking rules for that traffic. Your application handles the request normally.

> [!NOTE]
> Zen's built-in [Bypassed IPs](https://help.aikido.dev/zen-firewall/zen-features/bypassed-ips) feature uses request bypassing internally, triggered by a matching IP/CIDR. `Aikido::Zen.request_bypassed!` lets you bypass requests using your custom logic.

## What gets bypassed

* **Attack protection** — SQL injection, path traversal, command injection, and SSRF attacks are not detected.
* **Rate limiting** — never triggered.
* **IP blocking** — Known Threat Actors, Tor traffic blocking/monitoring, country blocking, and custom IP allow/block lists are not checked.
* **Bot traffic blocking** — not checked.
* **User blocking** — blocked users are not blocked.
* **Statistics** — the request isn't counted, and doesn't count against your monitored request quota.
* **Attack wave protection** — the request doesn't count towards wave detection.

## Usage

Insert your middleware directly after `Aikido::Zen::Middleware::ContextSetter`, so it runs after the request context is set up but before Zen's other middleware:

```ruby
# config/application.rb
class RequestBypasser
  def initialize(app)
    @app = app
  end

  def call(env)
    if your_custom_logic?(env)
      Aikido::Zen.request_bypassed! # Bypasses Zen for this request
    end

    @app.call(env)
  end
end

module YourApp
  class Application < Rails::Application
    # ...

    initializer "your_app.insert_request_bypasser", after: "aikido.add_middleware" do |app|
      app.middleware.insert_after Aikido::Zen::Middleware::ContextSetter, RequestBypasser
    end
  end
end
```

> [!WARNING]
> A bypassed request gets zero protection from Zen — no attack detection, no rate limiting, no blocking, no tracking. Ensure that your custom logic only bypasses requests that you fully trust.
