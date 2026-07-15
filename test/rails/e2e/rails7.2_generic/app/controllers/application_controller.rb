class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Add response header so tests can tell which Puma worker served the request.
  after_action { response.set_header("X-Worker-Pid", Process.pid.to_s) }
end
