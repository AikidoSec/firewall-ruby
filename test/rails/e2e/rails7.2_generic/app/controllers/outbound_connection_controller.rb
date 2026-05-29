class OutboundConnectionController < ApplicationController
  def show
    domain = params[:domain]

    # Outbound connection blocking has not been configured so the HTTP request
    # should not be blocked.
    response = Net::HTTP.get_response(URI("https://#{domain}"))

    render json: {status: response.code}
  rescue Aikido::Zen::OutboundConnectionBlockedError => error
    render json: {error: error.message}, status: :internal_server_error
  end
end
