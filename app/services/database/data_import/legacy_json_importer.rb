# frozen_string_literal: true

module Database
  module DataImport
    class LegacyJsonImporter
      def initialize(options:)
        @target_user_id = options.fetch(:target_user_id)
        @batch_importer = options.fetch(:batch_importer)
        @progress_reporter = ProgressReporter.new(options.fetch(:progress_callback))
        @validator = options.fetch(:validator)
        @batch_size = options.fetch(:batch_size)
        @max_file_bytes = options.fetch(:max_file_bytes)
      end

      def call(file)
        validate_file_size!(file)
        records_by_table = normalize_records(parse_payload(file))
        import_tables(records_by_table)
      end

      private

      def validate_file_size!(file)
        return unless file.size > @max_file_bytes

        raise ArgumentError,
              "Legacy JSON backups are limited to #{@max_file_bytes} bytes; export again using the new format."
      end

      def parse_payload(file)
        file.rewind
        raw_data = JSON.parse(file.read)
        raw_data = JSON.parse(raw_data) if raw_data.is_a?(String)
        return raw_data if raw_data.is_a?(Hash)

        raise ArgumentError, "Backup JSON root must be an object."
      end

      def normalize_records(raw_data)
        raw_data.each_with_object({}) do |(raw_name, records), normalized|
          table_name = raw_name.to_s.strip
          next unless DataTransferRegistry.include?(table_name)

          validate_table_records!(table_name, records)
          normalized[table_name] = records
        end
      end

      def validate_table_records!(table_name, records)
        return if records.is_a?(Array) && records.all?(Hash)

        raise ArgumentError, "Backup table '#{table_name}' must contain an array of objects."
      end

      def import_tables(records_by_table)
        entries = DataTransferRegistry.import_entries.select do |entry|
          records_by_table[entry.name].present?
        end
        @validator.validate_legacy_tables!(entries, records_by_table.keys)
        entries.each_with_index { |entry, index| import_table(entry, records_by_table, index, entries.size) }
      end

      def import_table(entry, records_by_table, index, total)
        notify_progress(entry, index, total)
        records_by_table.fetch(entry.name).each_slice(@batch_size) do |batch|
          @batch_importer.call(entry, batch, @target_user_id)
        end
      end

      def notify_progress(entry, index, total)
        @progress_reporter.table_started(entry.name, index, total)
      end
    end
  end
end
