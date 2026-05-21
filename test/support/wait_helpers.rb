# frozen_string_literal: true

module WaitHelpers
  def wait_until(timeout:)
    start_time = Time.now
    until yield || (Time.now - start_time) > timeout
      sleep 0.1
    end
  end
end
