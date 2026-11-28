# frozen_string_literal: true

class DataExportDownloadsController < ApplicationController
  before_action :authenticate_user!

  def show
    return head :not_found unless current_user.data_export.attached?

    blob = current_user.data_export.blob
    return head :not_found if expired_export?(blob)

    prepare_download_response(blob)
  end

  private

  def expired_export?(blob)
    return false unless blob.created_at < 1.hour.ago

    blob.purge_later
    true
  end

  def prepare_download_response(blob)
    set_download_headers(blob)
    self.response_body = stream_blob(blob)
  end

  def set_download_headers(blob)
    response.headers["Content-Type"] = blob.content_type.presence || "application/octet-stream"
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment",
      filename: blob.filename.sanitized
    )
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def stream_blob(blob)
    Enumerator.new do |stream|
      blob.download { |chunk| stream << chunk }
    end
  end
end
