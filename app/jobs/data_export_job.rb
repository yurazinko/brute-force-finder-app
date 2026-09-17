# frozen_string_literal: true

class DataExportJob < ApplicationJob
  def perform(user_id, tables = nil)
    user = User.find(user_id)

    Database::DataExportService.new(user, tables: tables).call do |progress, message|
      broadcast_progress("export", progress, message)
    end
  end

  private

  def broadcast_progress(dom_id, progress, message)
    broadcast_turbo_replace(
      "data_transfer_channel",
      target: dom_id,
      partial: "data_transfers/progress",
      locals: { id: dom_id, progress: progress, message: message }
    )
  end
end
