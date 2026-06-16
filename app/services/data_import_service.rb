# frozen_string_literal: true

class DataImportService
  TABLES_ORDER = %w[categories targets searches prompts results].freeze

  def initialize(file_path)
    @file_path = file_path
  end

  def call
    return false unless File.exist?(@file_path)

    raw_data = JSON.parse(File.read(@file_path))
    total_steps = TABLES_ORDER.size

    TABLES_ORDER.each_with_index do |table_name, index|
      records = raw_data[table_name]
      next if records.blank?

      if block_given?
        progress = ((index.to_f / total_steps) * 100).to_i
        yield(progress, "Importing #{table_name}...")
      end

      import_table(table_name, records)
    end

    FileUtils.rm_f(@file_path)
    yield(100, "Import completed successfully!") if block_given?
    true
  end

  private

  def import_table(table_name, records)
    records.each do |r|
      r["created_at"] = Time.zone.parse(r["created_at"]) if r["created_at"]
      r["updated_at"] = Time.zone.parse(r["updated_at"]) if r["updated_at"]
    end

    model = table_name.classify.constantize
    model.upsert_all(records, unique_by: :id)
  end
end
