class FileController < ApplicationController
  skip_forgery_protection if: -> { request.format.json? }

  # POST /file
  def create
    filename = params[:filename]

    if filename.present?
      file_path = File.join(File.dirname(__FILE__), filename)

      # Check if the file exists before trying to read it
      if File.exist?(file_path)
        contents = File.read(file_path)
        render json: {contents: contents, filename: filename} # Directly render JSON
      else
        render json: {error: "File not found"}, status: :not_found
      end
    else
      render json: {error: "Filename is required"}, status: :unprocessable_entity
    end
  end

  private
end
