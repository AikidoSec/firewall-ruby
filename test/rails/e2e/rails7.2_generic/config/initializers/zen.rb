if Rails.application.config.respond_to?(:zen)
  zen = Rails.application.config.zen
  zen.blocking_mode = true
  zen.polling_interval = 1
  zen.worker_process_polling_interval = 1
  zen.worker_process_heartbeat_interval = 1
  zen.realtime_settings_updates_enabled = true
end
