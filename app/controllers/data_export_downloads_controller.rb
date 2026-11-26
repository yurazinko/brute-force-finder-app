# frozen_string_literal: true

class DataExportDownloadsController < ApplicationController
  before_action :authenticate_user!

  def show
    return head :not_found unless current_user.data_export.attached?

    blob = current_user.data_export.blob
    if blob.created_at < 1.hour.ago
      blob.purge_later
      return head :not_found
    end

    response.headers["Content-Type"] = blob.content_type.presence || "application/octet-stream"
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment",
      filename: blob.filename.sanitized
    )
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    self.response_body = Enumerator.new do |stream|
      blob.download { |chunk| stream << chunk }
    end
  end
end
