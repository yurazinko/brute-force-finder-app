# frozen_string_literal: true

module Database
  class DataImportService
    include Rls::Context

    NDJSON_FORMAT = Database::DataExportService::FORMAT
    NDJSON_VERSION = Database::DataExportService::FORMAT_VERSION
    BATCH_SIZE = 500
    MAX_BATCH_BYTES = 8 * 1024 * 1024
    MAX_UPLOAD_BYTES = 512 * 1024 * 1024
    MAX_LEGACY_JSON_BYTES = 32 * 1024 * 1024
    MAX_NDJSON_LINE_BYTES = 16 * 1024 * 1024

    def initialize(file_path, user_id: nil)
      @file_path = file_path
      @user_id = user_id
      @id_maps = { categories: {}, targets: {}, searches: {}, target_patterns: {} }
      @import_succeeded = false
    end

    def call(&progress_callback)
      return false unless validate_file_exists

      target_user_id = determine_target_user_id
      validate_upload_size!
      DataImport::AdvisoryLock.synchronize(target_user_id) do
        import_file(target_user_id, &progress_callback)
      end
      complete_import(&progress_callback)
    rescue StandardError => e
      Rails.logger.error("[DataImportService] Critical failure: #{e.full_message}")
      raise
    ensure
      # Sidekiq retry needs the original file. Delete only after full success.
      FileUtils.rm_f(@file_path) if @import_succeeded
    end

    private

    def validate_file_exists
      Rails.logger.info("[DataImportService] Starting import from: #{@file_path}")
      return true if File.file?(@file_path)

      Rails.logger.error("[DataImportService] File NOT FOUND at path: #{@file_path}")
      false
    end

    def validate_upload_size!
      size = File.size(@file_path)
      return if size.positive? && size <= MAX_UPLOAD_BYTES

      raise ArgumentError, "Backup file must be between 1 byte and #{MAX_UPLOAD_BYTES} bytes."
    end

    def determine_target_user_id
      id = @user_id || self.class.current_rls_user_id
      raise "RLS Error: Target user context is missing!" if id.blank?

      Integer(id.to_s, 10)
    end

    def import_file(target_user_id, &progress_callback)
      File.open(@file_path, "r") do |file|
        first_line = file.gets(MAX_NDJSON_LINE_BYTES + 1)
        raise ArgumentError, "Backup file is empty." if first_line.blank?

        header = parse_header(first_line)
        importer = build_importer(header, target_user_id, &progress_callback)
        if ndjson_header?(header)
          importer.call(file, header)
        else
          importer.call(file)
        end
      end
    end

    def build_importer(header, target_user_id, &progress_callback)
      batch_importer = ->(entry, records, user_id) { import_batch(entry, records, user_id) }
      options = importer_options(target_user_id, batch_importer, progress_callback)

      if ndjson_header?(header)
        DataImport::NdjsonImporter.new(
          options: options.merge(max_batch_bytes: MAX_BATCH_BYTES, max_line_bytes: MAX_NDJSON_LINE_BYTES)
        )
      else
        DataImport::LegacyJsonImporter.new(options: options.merge(max_file_bytes: MAX_LEGACY_JSON_BYTES))
      end
    end

    def importer_options(target_user_id, batch_importer, progress_callback)
      {
        target_user_id: target_user_id,
        batch_importer: batch_importer,
        progress_callback: progress_callback,
        validator: DataImport::TableValidator.new,
        batch_size: BATCH_SIZE
      }
    end

    def parse_header(first_line)
      JSON.parse(first_line)
    rescue JSON::ParserError
      nil
    end

    def ndjson_header?(header)
      header.is_a?(Hash) && header["_format"] == NDJSON_FORMAT
    end

    def import_batch(entry, records, target_user_id)
      return if records.blank?

      with_rls_user(target_user_id) do
        entry.importer.new(records, target_user_id, @id_maps).call
      end
    end

    def complete_import(&progress_callback)
      progress_callback&.call(100, "Import completed successfully!")
      @import_succeeded = true
      true
    end
  end
end
