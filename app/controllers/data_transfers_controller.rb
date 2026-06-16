# frozen_string_literal: true

class DataTransfersController < ApplicationController
  def index; end

  def export
    DataExportJob.perform_async
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("export", partial: "data_transfers/progress",
                                                            locals: { id: "export", progress: 0, message: "Starting export job..." })
      end
      format.html { redirect_to data_transfers_path }
    end
  end

  def import
    if params[:file].present?
      # Тимчасово зберігаємо файл, щоб Sidekiq мав до нього доступ
      temp_path = Rails.root.join("tmp", "import_#{SecureRandom.hex}.json")
      File.binwrite(temp_path, params.expect(:file).read)

      DataImportJob.perform_async(temp_path.to_s)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("import", partial: "data_transfers/progress",
                                                              locals: { id: "import", progress: 0, message: "File uploaded. Starting sync..." })
        end
        format.html { redirect_to data_transfers_path }
      end
    else
      redirect_to data_transfers_path, alert: "Please upload a valid JSON file."
    end
  end
end
