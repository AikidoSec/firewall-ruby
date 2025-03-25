# frozen_string_literal: true

class BenchmarkController < ApplicationController
  # GET /benchmark
  def index
    sleep 1.0 / 1000.0 # 1ms to mimic a fast DB call
    render plain: "OK"
  end
end
