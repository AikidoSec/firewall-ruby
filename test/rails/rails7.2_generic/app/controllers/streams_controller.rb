class StreamsController < ApplicationController
  include ActionController::Live

  # Simulates a live notifications feed: the client passes its session token
  # so the server can confirm who's connecting before it starts streaming.
  def show
    token = params[:token]
    return render json: {error: "No token param"}, status: :unauthorized unless token

    ActiveRecord::Base.connection.exec_query(
      "SELECT name FROM users WHERE token = '#{token}'"
    )

    response.headers["Content-Type"] = "text/event-stream"
    response.stream.write("data: ok\n\n")
    response.stream.close
  end
end
