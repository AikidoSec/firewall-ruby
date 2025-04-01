# frozen_string_literal: true

class BenchmarkController < ApplicationController
  before_action :set_user

  # GET /benchmark
  def index
    sleep 1.0 / 1000.0 # 1ms to mimic a fast DB call
    render plain: "OK"
  end

  # GET /benchmark
  def with_user
    sleep 1.0 / 1000.0 # 1ms to mimic a fast DB call
    render plain: "OK"
  end

  def set_user
    # Track a pseudo-random user
    user_id = [1, 2, 3, 4, 5].sample
    pp "Using user_id='#{user_id}"
    Aikido::Zen.track_user({id: user_id, name: SecureRandom.hex(5)})
  end
end
