# frozen_string_literal: true

class DataImportJob
  include Sidekiq::Job

  def perform(file_path)
    DataImportService.new(file_path).call do |progress, message|
      broadcast_progress("import", progress, message)
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
