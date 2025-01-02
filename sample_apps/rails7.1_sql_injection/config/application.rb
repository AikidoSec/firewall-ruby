require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Cats
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults Rails.version[/\A\d+\.\d+/]

    if config.respond_to?(:autoload_lib)
      # Please, add to the `ignore` list any other `lib` subdirectories that do
      # not contain `.rb` files, or that should not be reloaded or eager loaded.
      # Common ones are `templates`, `generators`, or `middleware`, for example.
      config.autoload_lib(ignore: %w[assets tasks])
    else
      config.autoload_paths << Rails.root.join("lib")
      config.eager_load_paths << Rails.root.join("lib")

      %w[assets generators tasks templates].each do |subdir|
        Rails.autoloaders.main.ignore("#{Rails.root}/lib/#{subdir}")
      end
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
