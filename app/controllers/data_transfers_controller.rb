# frozen_string_literal: true

class DataTransfersController < ApplicationController
  def index; end

  def export
    DataExportJob.perform_async
    render_progress_stream("export", "Starting export job...")
  end

  def import
    if params[:file].present?
      temp_path = save_uploaded_file!
      DataImportJob.perform_async(temp_path, current_user.id)

      render_progress_stream("import", "File uploaded. Starting sync...")
    else
      redirect_to data_transfers_path, alert: "Please upload a valid JSON file."
    end
  end

  private

  def render_progress_stream(dom_id, message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id,
          partial: "data_transfers/progress",
          locals: { id: dom_id, progress: 0, message: message }
        )
      end
      format.html { redirect_to data_transfers_path }
    end
  end

  def save_uploaded_file!
    temp_path = Rails.root.join("tmp", "import_#{SecureRandom.hex}.json")
    File.binwrite(temp_path, params.expect(:file).read)
    temp_path.to_s
  end
end
