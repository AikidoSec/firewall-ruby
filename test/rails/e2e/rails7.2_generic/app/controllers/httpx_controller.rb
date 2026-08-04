# frozen_string_literal: true

require "httpx"

class HttpxController < ApplicationController
  # Port 1 on localhost is never listening, so the connection is refused
  # immediately and HTTPX emits an ErrorResponse instead of a real response.
  UNREACHABLE_URL = "http://127.0.0.1:1/"

  def show
    response = client.get(url)

    if response.is_a?(HTTPX::ErrorResponse)
      render json: {result: "error_response", error: response.error.class.name}
    else
      render json: {result: "response", status: response.status}
    end
  rescue Aikido::Zen::UnderAttackError, Aikido::Zen::OutboundConnectionBlockedError => err
    render json: {error: err.message}, status: :internal_server_error
  end

  private

  def unreachable?
    params[:mode] == "unreachable"
  end

  # The reachable target is the mock Aikido server rather than this app, since
  # a request back to our own host:port would (correctly) be flagged as SSRF:
  # the incoming Host header counts as user input.
  def url
    unreachable? ? UNREACHABLE_URL : "#{ENV.fetch("AIKIDO_ENDPOINT")}/config"
  end

  def client
    client = HTTPX.with(timeout: {connect_timeout: 1, request_timeout: 5})
    return client if unreachable?

    client.with(headers: {"Authorization" => ENV.fetch("AIKIDO_TOKEN")})
  end
end
