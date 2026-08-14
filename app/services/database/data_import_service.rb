# frozen_string_literal: true

module Database
  class DataImportService
    include Rls::Context

    IMPORTERS = {
      "categories" => Importers::CategoryImporter,
      "targets" => Importers::TargetImporter,
      "searches" => Importers::SearchImporter,
      "prompts" => Importers::PromptImporter,
      "results" => Importers::ResultImporter
    }.freeze

    def initialize(file_path, user_id: nil)
      @file_path = file_path
      @user_id = user_id
      @id_maps = { "categories" => {}, "targets" => {}, "searches" => {} }
    end

    def call(&)
      return false unless validate_file_exists

      raw_data = load_and_sanitize_data
      target_user_id = determine_target_user_id

      with_rls_user(target_user_id) do
        process_import(raw_data, target_user_id, &)
      end

      yield(100, "Import completed successfully!") if block_given?
      true
    rescue StandardError => e
      Rails.logger.error("[DataImportService] Critical failure: #{e.full_message}")
      raise e
    ensure
      FileUtils.rm_f(@file_path)
    end

    private

    def validate_file_exists
      Rails.logger.info("[DataImportService] Starting import from: #{@file_path}")
      return true if File.exist?(@file_path)

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
      parsed.transform_keys { |key| key.to_s.tr('"', "").strip }
    end

    def process_import(raw_data, target_user_id, &)
      total_steps = IMPORTERS.size

      IMPORTERS.each_with_index do |(table_name, importer_class), index|
        records = raw_data[table_name]
        next if records.blank?

        notify_progress(index, total_steps, table_name, &)
        importer_class.new(records, target_user_id, @id_maps).call
      end
    end

    def notify_progress(index, total_steps, table_name)
      return unless block_given?

      progress = ((index.to_f / total_steps) * 100).to_i
      yield(progress, "Importing #{table_name}...")
    end
  end
end
