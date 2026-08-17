require_relative "boot"

require "rails/all"

require "aikido-zen"
Aikido::Zen.protect!

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Test-only middleware mirroring docs/request-bypassing.md's example.
class RequestBypasser
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["HTTP_X_BYPASS_ZEN"] == "true"
      Aikido::Zen.request_bypassed! # Bypasses Zen for this request
    end

    @app.call(env)
  end
end

module Generic
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    initializer "generic.insert_request_bypasser", after: "aikido.add_middleware" do |app|
      app.middleware.insert_after Aikido::Zen::Middleware::ContextSetter, RequestBypasser
    end
  end
end
