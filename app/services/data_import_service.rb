# frozen_string_literal: true

class DataImportService
  TABLES_ORDER = %w[categories targets searches prompts results].freeze

  def initialize(file_path)
    @file_path = file_path
  end

  def call
    return false unless File.exist?(@file_path)

    raw_data = load_and_sanitize_data

    ActiveRecord::Base.transaction do
      process_import(raw_data) { |progress, msg| yield(progress, msg) if block_given? }
      FileUtils.rm_f(@file_path)
    end

    yield(100, "Import completed successfully!") if block_given?
    true
  rescue StandardError => e
    Rails.logger.error("[DataImportService] Critical failure: #{e.full_message}")
    false
  end

  private

  def load_and_sanitize_data
    parsed_json = JSON.parse(File.read(@file_path))
    parsed_json.transform_keys { |key| key.delete('"') }
  end

  def process_import(raw_data)
    total_steps = TABLES_ORDER.size

    TABLES_ORDER.each_with_index do |table_name, index|
      records = raw_data[table_name]
      next if records.blank?

      progress = ((index.to_f / total_steps) * 100).to_i
      yield(progress, "Importing #{table_name}...")

      import_table(table_name, records)
      reset_postgresql_sequence!(table_name)
    end
  end

  def import_table(table_name, records)
    model = table_name.classify.constantize
    parsed_records = parse_timestamps(records)

    model.upsert_all(parsed_records, unique_by: :id)
  end

  def parse_timestamps(records)
    records.each do |r|
      r["created_at"] = Time.zone.parse(r["created_at"]) if r["created_at"]
      r["updated_at"] = Time.zone.parse(r["updated_at"]) if r["updated_at"]
    end
  end

  def reset_postgresql_sequence!(table_name)
    return unless ActiveRecord::Base.connection.adapter_name.downcase.include?("postgre")

    model = table_name.classify.constantize
    sequence_name = "#{model.table_name}_id_seq"

    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      SELECT setval('#{sequence_name}', COALESCE((SELECT MAX(id) FROM #{model.table_name}), 1), true);
    SQL
  end
end
