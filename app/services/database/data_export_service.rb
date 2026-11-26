# frozen_string_literal: true

require "tempfile"

module Database
  class DataExportService
    BATCH_SIZE = 1_000
    FORMAT = "brute-force-finder-ndjson"
    FORMAT_VERSION = 2

    attr_reader :user, :requested_tables

    def initialize(user, tables: nil)
      @user = user
      @requested_tables = DataTransferRegistry.resolve_selection(tables)
    end

    def call(&progress_callback)
      datasets = scoped_datasets

      Tempfile.create(["database-export-", ".ndjson"], Rails.root.join("tmp")) do |file|
        generate_export(file, datasets, &progress_callback)
        file.flush
        file.rewind
        attach_export_file(file)
      end

      notify_completion(&progress_callback) if progress_callback
      true
    end

    private

    def scoped_datasets
      requested_tables.map do |table_name|
        entry = DataTransferRegistry.fetch(table_name)
        [table_name, entry.scope.call(user)]
      end
    end

    def generate_export(io, datasets, &)
      header = {
        "_format" => FORMAT,
        "version" => FORMAT_VERSION,
        "tables" => datasets.map(&:first)
      }
      write_line(io, header)

      datasets.each_with_index do |(table_name, scope), index|
        notify_progress(index, datasets.size, table_name, &) if block_given?
        scope.find_each(batch_size: BATCH_SIZE) do |record|
          write_line(io, "table" => table_name, "record" => record.as_json)
        end
      end
    end

    def write_line(io, payload)
      io.write(JSON.generate(payload))
      io.write("\n")
    end

    def attach_export_file(io)
      previous_blob = user.data_export.blob if user.data_export.attached?
      filename = "export-user-#{user.id}-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.ndjson"

      user.data_export.attach(
        io: io,
        filename: filename,
        content_type: "application/x-ndjson"
      )

      return unless previous_blob && user.data_export.blob&.id != previous_blob.id

      previous_blob.purge_later
    end

    def notify_progress(index, total_steps, table_name)
      progress = total_steps.zero? ? 95 : ((index.to_f / total_steps) * 95).to_i
      yield(progress, "Exporting #{table_name}...")
    end

    def notify_completion
      download_url = Rails.application.routes.url_helpers.data_transfers_download_path

      html = "Done! Click <a href='#{download_url}' class='text-breeze-accent " \
             "underline font-semibold'>here</a> to download (available for 1 hour while signed in)."
      yield(100, html)
    end
  end
end
