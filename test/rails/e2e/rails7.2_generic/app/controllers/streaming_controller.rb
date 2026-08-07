# frozen_string_literal: true

# Exercises a sink from inside ActionController::Live, which runs the action in
# its own thread. See https://github.com/AikidoSec/firewall-ruby/issues/357
class StreamingController < ApplicationController
  include ActionController::Live

  def show
    response.headers["Content-Type"] = "text/event-stream"

    content = File.read(params[:path])
    response.stream.write("data: #{content.bytesize}\n\n")
  rescue => err
    response.stream.write("data: #{err.class}\n\n")
  ensure
    response.stream.close
  end
end
