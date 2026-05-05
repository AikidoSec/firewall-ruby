module Api
  module V1
    class ProfilesController < BaseController
      include ActionController::Cookies

      def show
        token = cookies[:token]
        return render json: {error: "No token cookie"}, status: :unauthorized unless token

        results = ActiveRecord::Base.connection.exec_query(
          "SELECT name, secret FROM users WHERE token = '#{token}'"
        )
        render json: results.rows
      end
    end
  end
end
