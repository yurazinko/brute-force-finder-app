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
      with_import_lock(target_user_id) do
        import_file(target_user_id, &progress_callback)
      end

      progress_callback&.call(100, "Import completed successfully!")
      @import_succeeded = true
      true
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

    # Hold a session advisory lock across batch transactions so two simultaneous
    # restores for the same user cannot race on natural-key matching. The same
    # checked-out connection is reused by Rls::Context on this thread.
    def with_import_lock(target_user_id)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        lock_namespace = 729_194
        lock_sql = "SELECT pg_advisory_lock(#{lock_namespace}, #{Integer(target_user_id)})"
        unlock_sql = "SELECT pg_advisory_unlock(#{lock_namespace}, #{Integer(target_user_id)})"
        connection.select_value(lock_sql)
        begin
          yield
        ensure
          begin
            connection.select_value(unlock_sql)
          rescue StandardError
            ActiveRecord::Base.connection_pool.remove(connection)
            raise
          end
        end
      end
    end

    def import_file(target_user_id, &)
      File.open(@file_path, "r") do |file|
        first_line = file.gets(MAX_NDJSON_LINE_BYTES + 1)
        raise ArgumentError, "Backup file is empty." if first_line.blank?

        header = begin
          JSON.parse(first_line)
        rescue JSON::ParserError
          nil
        end

        if header.is_a?(Hash) && header["_format"] == NDJSON_FORMAT
          import_ndjson(file, header, target_user_id, &)
        else
          import_legacy_json(file, target_user_id, &)
        end
      end
    end

    def import_ndjson(file, header, target_user_id, &progress_callback)
      unless header["version"].to_i == NDJSON_VERSION && header["tables"].is_a?(Array)
        raise ArgumentError, "Unsupported backup format/version."
      end

      table_names = header["tables"].map(&:to_s)
      validate_declared_tables!(table_names)

      entry_by_name = DataTransferRegistry.entries.index_by(&:name)
      expected_order = DataTransferRegistry.table_names
      declared_tables = table_names.to_set
      last_table_index = -1
      current_table = nil
      current_buffer = []
      current_buffer_bytes = 0
      line_number = 1
      total_tables = table_names.size

      while (line = file.gets(MAX_NDJSON_LINE_BYTES + 1))
        line_number += 1
        if line.bytesize > MAX_NDJSON_LINE_BYTES
          raise ArgumentError, "Backup line #{line_number} exceeds the maximum line size."
        end
        next if line.strip.empty?

        payload = parse_json_line(line, line_number)
        unless payload.is_a?(Hash) && payload["table"].present? && payload.key?("record")
          raise ArgumentError, "Backup line #{line_number} must contain table and record."
        end

        table_name = payload["table"].to_s
        unless DataTransferRegistry.include?(table_name) && declared_tables.include?(table_name)
          raise ArgumentError, "Backup line #{line_number} references undeclared table '#{table_name}'."
        end

        table_index = expected_order.index(table_name)
        if table_index.nil? || table_index < last_table_index
          raise ArgumentError, "Backup tables are not in dependency-safe order near line #{line_number}."
        end

        if table_name != current_table
          if current_table.present?
            flush_import_buffer(entry_by_name.fetch(current_table), current_buffer,
                                target_user_id)
          end
          current_buffer = []
          current_buffer_bytes = 0
          current_table = table_name

          table_number = table_names.index(table_name).to_i
          progress = total_tables.zero? ? 95 : ((table_number.to_f / total_tables) * 95).to_i
          progress_callback&.call(progress, "Importing #{table_name}...")
        end

        record = payload["record"]
        raise ArgumentError, "Backup record at line #{line_number} must be an object." unless record.is_a?(Hash)

        current_buffer << record
        current_buffer_bytes += line.bytesize
        last_table_index = table_index

        next unless current_buffer.size >= BATCH_SIZE || current_buffer_bytes >= MAX_BATCH_BYTES

        flush_import_buffer(entry_by_name.fetch(current_table), current_buffer, target_user_id)
        current_buffer = []
        current_buffer_bytes = 0
      end

      flush_import_buffer(entry_by_name.fetch(current_table), current_buffer, target_user_id) if current_table.present?
    end

    def flush_import_buffer(entry, records, target_user_id)
      return if records.blank?

      import_batch(entry, records, target_user_id)
    end

    def import_legacy_json(file, target_user_id, &progress_callback)
      if File.size(@file_path) > MAX_LEGACY_JSON_BYTES
        raise ArgumentError,
              "Legacy JSON backups are limited to #{MAX_LEGACY_JSON_BYTES} bytes; export again using the new format."
      end

      file.rewind
      raw_data = JSON.parse(file.read)
      raw_data = JSON.parse(raw_data) if raw_data.is_a?(String)
      raise ArgumentError, "Backup JSON root must be an object." unless raw_data.is_a?(Hash)

      normalized = raw_data.each_with_object({}) do |(raw_name, records), result|
        table_name = raw_name.to_s.strip
        next unless DataTransferRegistry.include?(table_name)

        unless records.is_a?(Array) && records.all?(Hash)
          raise ArgumentError, "Backup table '#{table_name}' must contain an array of objects."
        end

        result[table_name] = records
      end

      entries = DataTransferRegistry.import_entries.select { |entry| normalized[entry.name].present? }
      validate_dependencies!(entries, normalized.keys)
      entries.each_with_index do |entry, index|
        progress_callback&.call(
          entries.empty? ? 95 : ((index.to_f / entries.size) * 95).to_i,
          "Importing #{entry.name}..."
        )
        normalized.fetch(entry.name).each_slice(BATCH_SIZE) do |batch|
          import_batch(entry, batch, target_user_id)
        end
      end
    end

    def validate_declared_tables!(table_names, enforce_order: true)
      unknown_tables = table_names.reject { |name| DataTransferRegistry.include?(name) }
      if unknown_tables.any?
        raise ArgumentError,
              "Backup contains unsupported tables: #{unknown_tables.uniq.join(', ')}"
      end
      raise ArgumentError, "Backup declares duplicate table names." unless table_names.uniq == table_names

      if enforce_order
        registry_order = DataTransferRegistry.table_names
        sorted_names = table_names.sort_by { |name| registry_order.index(name) || Float::INFINITY }
        unless sorted_names == table_names
          raise ArgumentError, "Backup table declarations are not in dependency-safe order."
        end
      end

      expanded = DataTransferRegistry.resolve_selection(table_names)
      missing_dependencies = expanded - table_names
      return if missing_dependencies.empty?

      raise ArgumentError, "Backup is missing dependencies: #{missing_dependencies.join(', ')}"
    end

    def validate_dependencies!(entries, provided_names)
      # Legacy JSON object key order is semantically irrelevant; importers
      # process the allow-listed registry in dependency-safe order.
      validate_declared_tables!(provided_names, enforce_order: false)
      entries.each do |entry|
        missing = entry.dependencies.reject { |dependency| provided_names.include?(dependency) }
        next if missing.empty?

        raise ArgumentError, "Backup table '#{entry.name}' is missing dependencies: #{missing.join(', ')}"
      end
    end

    def import_batch(entry, records, target_user_id)
      return if records.blank?

      with_rls_user(target_user_id) do
        entry.importer.new(records, target_user_id, @id_maps).call
      end
    end

    def parse_json_line(line, line_number)
      JSON.parse(line)
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid JSON at backup line #{line_number}: #{e.message}"
    end
  end
end
