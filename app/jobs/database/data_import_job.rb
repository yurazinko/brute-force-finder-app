# frozen_string_literal: true

module Database
  class DataImportJob < ApplicationJob
    sidekiq_options queue: :default, retry: 5

    sidekiq_retries_exhausted do |message, error|
      file_path = message.dig("args", 0)
      FileUtils.rm_f(file_path) if file_path.present?
      Rails.logger.error("[DataImportJob] Retries exhausted: #{error.class}: #{error.message}")
    end

    def perform(file_path, user_id)
      Database::DataImportService.new(file_path, user_id: user_id).call do |progress, message|
        broadcast_progress("import", progress, message)
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
end
