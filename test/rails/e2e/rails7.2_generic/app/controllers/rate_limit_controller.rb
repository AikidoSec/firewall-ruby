# frozen_string_literal: true

class RateLimitController < ApplicationController
  def show
    render json: {"ok" => true}
  end
end
