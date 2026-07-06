# frozen_string_literal: true

class WorkerProcessController < ApplicationController
  def show
    render json: {
      "pid" => Process.pid,
      "configUpdatedAt" => Aikido::Zen.runtime_settings.updated_at&.to_i,
      "blockingMode" => Aikido::Zen.blocking_mode?,
      "blockedUserIds" => Aikido::Zen.runtime_settings.blocked_user_ids
    }
  end
end
