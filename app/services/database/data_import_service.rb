# frozen_string_literal: true

module Database
  class DataImportService
    include Rls::Context

    def initialize(file_path, user_id: nil)
      @file_path = file_path
      @user_id = user_id
      @id_maps = { categories: {}, targets: {}, searches: {}, target_patterns: {} }
      @import_succeeded = false
    end

    def call(&)
      return false unless validate_file_exists

      execute_import(load_and_sanitize_data, determine_target_user_id, &)
      @import_succeeded = true
      true
    rescue StandardError => e
      Rails.logger.error("[DataImportService] Critical failure: #{e.full_message}")
      raise
    ensure
      # Keep the uploaded file after a failure: Sidekiq may retry this job.
      # The job's retries-exhausted hook is responsible for final cleanup.
      FileUtils.rm_f(@file_path) if @import_succeeded
    end

    private

    def execute_import(raw_data, target_user_id, &progress_callback)
      with_rls_user(target_user_id) do
        ActiveRecord::Base.transaction do
          process_import(raw_data, target_user_id, &progress_callback)
        end
      end

      progress_callback&.call(100, "Import completed successfully!")
    end

    def validate_file_exists
      Rails.logger.info("[DataImportService] Starting import from: #{@file_path}")
      return true if File.file?(@file_path)

      Rails.logger.error("[DataImportService] File NOT FOUND at path: #{@file_path}")
      false
    end

    def determine_target_user_id
      id = @user_id || self.class.current_rls_user_id
      raise "RLS Error: Target user context is missing!" if id.blank?

      id
    end

    def load_and_sanitize_data
      parsed = JSON.parse(File.read(@file_path))
      parsed = JSON.parse(parsed) if parsed.is_a?(String)
      raise ArgumentError, "Backup JSON root must be an object." unless parsed.is_a?(Hash)

      parsed.each_with_object({}.with_indifferent_access) do |(raw_table_name, records), normalized|
        table_name = raw_table_name.to_s.strip
        next unless DataTransferRegistry.include?(table_name)

        unless records.is_a?(Array) && records.all?(Hash)
          raise ArgumentError, "Backup table '#{table_name}' must contain an array of objects."
        end

        normalized[table_name] = records
      end
    end

    def process_import(raw_data, target_user_id, &)
      # Serialize imports for one account so two uploads of the same backup cannot
      # race each other through the natural-key deduplication checks.
      User.lock.find(target_user_id)

      entries = DataTransferRegistry.import_entries.select do |entry|
        raw_data.key?(entry.name) && raw_data[entry.name].any?
      end

      entries.each_with_index do |entry, index|
        notify_progress(index, entries.size, entry.name, &) if block_given?
        entry.importer.new(raw_data[entry.name], target_user_id, @id_maps).call
      end
    end

    def notify_progress(index, total_steps, table_name)
      progress = total_steps.zero? ? 95 : ((index.to_f / total_steps) * 95).to_i
      yield(progress, "Importing #{table_name}...")
    end
  end
end
