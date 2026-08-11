# frozen_string_literal: true

class ErrorsController < ApplicationController
  # Custom 404 page for test/e2e/attack_wave_test.rb.
  def not_found
    render plain: "Not Found", status: :not_found
  end
end
