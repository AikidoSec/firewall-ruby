class StreamsController < ApplicationController
  include ActionController::Live

  def show
    response.headers["Content-Type"] = "text/event-stream"
    response.stream.write("data: ok\n\n")
  ensure
    response.stream.close
  end

  def query
    response.headers["Content-Type"] = "text/event-stream"

    ActiveRecord::Base.connection.exec_query(
      "SELECT name, secret FROM users WHERE token = '#{params[:token]}'"
    )
    response.stream.write("data: ok\n\n")
  rescue => err
    response.stream.write("data: #{err.cause.class}\n\n")
  ensure
    response.stream.close
  end
end
