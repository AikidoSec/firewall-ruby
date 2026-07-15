# frozen_string_literal: true

class PathTraversalController < ApplicationController
  def show
    path = params[:path]

    content = File.read(path)

    render plain: content
  rescue Aikido::Zen::UnderAttackError => err
    render json: {error: err.message}, status: :internal_server_error
  end
end
