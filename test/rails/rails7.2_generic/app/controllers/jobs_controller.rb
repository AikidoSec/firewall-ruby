class JobsController < ApplicationController
  def create
    job = QueryJob
    job = job.set(wait: params[:wait].to_f.seconds) if params[:wait]
    job.perform_later(params[:token])

    head :accepted
  end
end
