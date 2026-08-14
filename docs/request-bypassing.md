# Bypass Zen for a specific request

To disable Zen for a specific request, call `Aikido::Zen.request_bypassed!` from a Rack middleware. This bypasses Zen's security checks and stats collection for that request.

> [!NOTE]
> Zen already has a built-in feature for bypassing specific IP addresses. This feature offers more flexibility, letting you bypass Zen for a request based on any criteria you choose.

`Aikido::Zen.request_bypassed!` needs the request's context to already be set up, so your middleware must run after Zen's `ContextSetter` middleware. The following example shows how to bypass a specific request in a Rails application:

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
> Use this feature with caution, as it can potentially expose your application to security risks if not used properly.
