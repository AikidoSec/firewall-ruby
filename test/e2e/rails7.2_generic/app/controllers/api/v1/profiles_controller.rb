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

      def update
        token = cookies[:token]
        return render json: {error: "No token cookie"}, status: :unauthorized unless token

        results = ActiveRecord::Base.connection.exec_query(
          # Trigger SQL injection detection with param value "NEW_SECRET', name='NEW_NAME"
          "UPDATE users SET secret='NEW_SECRET', name='NEW_NAME' WHERE token='#{token}'"
        )
        render json: results.rows
      end
    end
  end
end
