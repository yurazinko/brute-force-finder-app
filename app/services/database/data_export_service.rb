# frozen_string_literal: true

require "tempfile"

module Database
  class DataExportService
    BATCH_SIZE = 1_000

    attr_reader :user, :requested_tables

    def initialize(user, tables: nil)
      @user = user
      @requested_tables = DataTransferRegistry.resolve_selection(tables)
    end

    def call(&progress_callback)
      datasets = scoped_datasets

      Tempfile.create(["database-export-", ".json"], Rails.root.join("tmp")) do |file|
        generate_export_json(file, datasets, &progress_callback)
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

    # Write each record as it is fetched instead of materializing every table in
    # memory with Relation#as_json. This exports every matching row in batches.
    def generate_export_json(io, datasets, &)
      io.write("{")

      datasets.each_with_index do |(table_name, scope), index|
        notify_progress(index, datasets.size, table_name, &) if block_given?
        io.write(",") unless index.zero?
        io.write(JSON.generate(table_name))
        io.write(":")
        write_relation_rows(io, scope)
      end

      io.write("}")
    end

    def write_relation_rows(io, relation)
      io.write("[")
      first_record = true

      relation.find_each(batch_size: BATCH_SIZE) do |record|
        io.write(",") unless first_record
        io.write(JSON.generate(record.as_json))
        first_record = false
      end

      io.write("]")
    end

    def attach_export_file(io)
      filename = "export-user-#{user.id}-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.json"

      user.data_export.attach(
        io: io,
        filename: filename,
        content_type: "application/json"
      )
    end

    def notify_progress(index, total_steps, table_name)
      progress = total_steps.zero? ? 95 : ((index.to_f / total_steps) * 95).to_i
      yield(progress, "Exporting #{table_name}...")
    end

    def notify_completion
      download_url = Rails.application.routes.url_helpers.rails_blob_path(
        user.data_export.blob,
        expires_in: 1.hour,
        disposition: "attachment",
        only_path: true
      )

      html = "Done! Click <a href='#{download_url}' download class='text-breeze-accent " \
             "underline font-semibold'>here</a> to download (link expires in 1 hour)."
      yield(100, html)
    end
  end
end
