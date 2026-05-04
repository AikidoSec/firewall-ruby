if Rails.application.config.respond_to?(:zen)
  Rails.application.config.zen.blocking_mode = true
end
