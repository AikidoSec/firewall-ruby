require "resolv"

class ResolvController < ApplicationController
  def lookup
    return unless request.post?

    hostname = params[:hostname]

    begin
      @ip = Resolv.getaddress(hostname)
      flash.now[:notice] = "The IP address for #{hostname} is #{@ip}"
    rescue Resolv::ResolvError
      flash.now[:alert] = "Could not resolve #{hostname}"
    end
  end
end
