# If you don't want to depend on ENV vars, this is another way to
# configure the Zen library.
if Rails.application.config.respond_to?(:zen)
  Rails.application.config.zen.blocking_mode = true
  # Rails.application.config.zen.stored_ssrf = false
  # Rails.application.config.zen.imds_allowed_hosts << "known-safe-hostname"
end
