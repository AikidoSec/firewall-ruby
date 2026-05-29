if Rails.application.config.respond_to?(:zen)
  zen = Rails.application.config.zen
  zen.blocking_mode = true
end
