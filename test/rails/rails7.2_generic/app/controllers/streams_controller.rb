class StreamsController < ApplicationController
  include ActionController::Live

  def show
    response.headers["Content-Type"] = "text/event-stream"
    response.stream.write("data: ok\n\n")
  ensure
    response.stream.close
  end
end
