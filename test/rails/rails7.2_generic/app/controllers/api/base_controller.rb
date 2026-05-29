module Api
  class BaseController < ApplicationController
    skip_forgery_protection
    before_action :set_json_format

    rescue_from StandardError do |error|
      render json: {
        error: error.class.name,
        message: error.message,
        cause: error.cause
      }, status: :internal_server_error
    end

    private

    def set_json_format
      request.format = :json
    end
  end
end
