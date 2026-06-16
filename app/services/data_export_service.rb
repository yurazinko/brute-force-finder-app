# frozen_string_literal: true

class DataExportService
  TABLES = %w[categories targets searches prompts results].freeze

  attr_reader :output_path

  def initialize(output_path = nil)
    @output_path = output_path || default_output_path
  end

  def call
    collect_records

    if block_given?
      yield(100, "Done! Click <a href='/#{@output_path.basename}' download class='text-indigo-600 underline font-semibold'>here</a> to download.")
    end
    true
  end

  private

  def collect_records
    export_data = {}
    total_steps = TABLES.size

    TABLES.each_with_index do |table, index|
      if block_given?
        progress = ((index.to_f / total_steps) * 100).to_i
        yield(progress, "Exporting #{table}...")
      end

      export_data[table] = ActiveRecord::Base.connection.execute("SELECT * FROM #{table}").to_a
    end

    @output_path.write(JSON.pretty_generate(export_data))
  end

  def default_output_path
    timestamp = Time.current.strftime("%Y-%m-%d-%H%M%S") # Гарний формат: 2026-06-16-164036
    Rails.public_path.join("export-#{timestamp}.json")
  end
end
