if Rails.application.config.respond_to?(:zen)
  zen = Rails.application.config.zen
  zen.blocking_mode = true

  if Rails.env.test?
    zen.logger = ActiveSupport::Logger.new(File::NULL)
  end
end
