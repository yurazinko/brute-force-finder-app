# frozen_string_literal: true

module Database
  module DataImport
    class NdjsonImporter
      def initialize(options:)
        @target_user_id = options.fetch(:target_user_id)
        @batch_importer = options.fetch(:batch_importer)
        @progress_reporter = ProgressReporter.new(options.fetch(:progress_callback))
        @validator = options.fetch(:validator)
        @batch_size = options.fetch(:batch_size)
        @max_batch_bytes = options.fetch(:max_batch_bytes)
        @max_line_bytes = options.fetch(:max_line_bytes)
      end

      def call(file, header)
        table_names = validate_header!(header)
        initialize_stream_state(table_names)
        process_stream(file)
        flush_buffer
      end

      private

      def validate_header!(header)
        unless header["version"].to_i == DataImportService::NDJSON_VERSION && header["tables"].is_a?(Array)
          raise ArgumentError, "Unsupported backup format/version."
        end

        table_names = header["tables"].map(&:to_s)
        @validator.validate_ndjson_tables!(table_names)
        table_names
      end

      def initialize_stream_state(table_names)
        @table_names = table_names
        @declared_tables = table_names.to_set
        @declared_positions = table_names.each_with_index.to_h
        @registry_positions = DataTransferRegistry.table_names.each_with_index.to_h
        @entry_by_name = DataTransferRegistry.entries.index_by(&:name)
        @last_table_index = -1
        @current_table = nil
        @buffer = []
        @buffer_bytes = 0
        @line_number = 1
      end

      def process_stream(file)
        while (line = file.gets(@max_line_bytes + 1))
          process_line(line)
        end
      end

      def process_line(line)
        @line_number += 1
        validate_line_size!(line)
        return if line.strip.empty?

        payload = parse_json_line(line)
        validate_payload!(payload)
        switch_table(payload.fetch("table").to_s)
        append_record(payload.fetch("record"), line.bytesize)
      end

      def validate_line_size!(line)
        return unless line.bytesize > @max_line_bytes

        raise ArgumentError, "Backup line #{@line_number} exceeds the maximum line size."
      end

      def parse_json_line(line)
        JSON.parse(line)
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid JSON at backup line #{@line_number}: #{e.message}"
      end

      def validate_payload!(payload)
        return if payload.is_a?(Hash) && payload["table"].present? && payload.key?("record")

        raise ArgumentError, "Backup line #{@line_number} must contain table and record."
      end

      def switch_table(table_name)
        unless DataTransferRegistry.include?(table_name) && @declared_tables.include?(table_name)
          raise_undeclared_table!(table_name)
        end

        table_index = @registry_positions[table_name]
        raise_out_of_order_table! if table_index.nil? || table_index < @last_table_index

        start_table(table_name) unless table_name == @current_table
        @last_table_index = table_index
      end

      def raise_undeclared_table!(table_name)
        raise ArgumentError, "Backup line #{@line_number} references undeclared table '#{table_name}'."
      end

      def raise_out_of_order_table!
        raise ArgumentError, "Backup tables are not in dependency-safe order near line #{@line_number}."
      end

      def start_table(table_name)
        flush_buffer
        @current_table = table_name
        @buffer = []
        @buffer_bytes = 0
        notify_table_progress(table_name)
      end

      def notify_table_progress(table_name)
        @progress_reporter.table_started(
          table_name, @declared_positions.fetch(table_name), @table_names.size
        )
      end

      def append_record(record, line_bytes)
        raise ArgumentError, "Backup record at line #{@line_number} must be an object." unless record.is_a?(Hash)

        @buffer << record
        @buffer_bytes += line_bytes
        flush_buffer if batch_limit_reached?
      end

      def batch_limit_reached?
        @buffer.size >= @batch_size || @buffer_bytes >= @max_batch_bytes
      end

      def flush_buffer
        return if @current_table.nil? || @buffer.empty?

        @batch_importer.call(@entry_by_name.fetch(@current_table), @buffer, @target_user_id)
        @buffer = []
        @buffer_bytes = 0
      end
    end
  end
end
