# frozen_string_literal: true

class DataExportJob
  include Sidekiq::Job

  def perform
    DataExportService.new.call do |progress, message|
      broadcast_progress("export", progress, message)
    end
  end

  private

  def broadcast_progress(dom_id, progress, message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "data_transfer_channel",
      target: dom_id,
      partial: "data_transfers/progress",
      locals: { id: dom_id, progress: progress, message: message }
    )
  end
end
