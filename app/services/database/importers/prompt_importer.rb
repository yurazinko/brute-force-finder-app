# frozen_string_literal: true

module Database
  module Importers
    class PromptImporter < BaseImporter
      GLOBAL_UNIQUE_INDEX = :index_global_prompts_on_search_and_query
      TARGET_UNIQUE_INDEX = :index_prompts_on_search_target_and_query
      ON_DUPLICATE_SQL = Arel.sql(
        "status = EXCLUDED.status, error_message = EXCLUDED.error_message, updated_at = EXCLUDED.updated_at"
      )

      def call
        rows = records.filter_map { |record| build_prompt_row(record) }
        return if rows.empty?

        global_rows, targeted_rows = rows.partition { |row| row[:target_id].nil? }
        upsert_rows(global_rows, GLOBAL_UNIQUE_INDEX) if global_rows.any?
        upsert_rows(targeted_rows, TARGET_UNIQUE_INDEX) if targeted_rows.any?
      end

      private

      def build_prompt_row(record)
        search_id = resolve_search_id(record)
        raise ArgumentError, "Prompt #{record[:id].inspect} has no query text." if record[:full_query_text].blank?

        {
          search_id: search_id,
          target_id: resolve_target_id(record),
          full_query_text: record[:full_query_text],
          status: normalize_status(record[:status]),
          error_message: record[:error_message],
          created_at: imported_timestamp(record[:created_at]),
          updated_at: imported_timestamp(record[:updated_at])
        }
      end

      def resolve_search_id(record)
        search_id = mapped_id(:searches, record[:search_id])
        return search_id if search_id.present?

        raise ArgumentError, "Prompt #{record[:id].inspect} references a search that was not imported."
      end

      def resolve_target_id(record)
        source_target_id = record[:target_id]
        return nil if source_target_id.blank?

        target_id = mapped_id(:targets, source_target_id)
        return target_id if target_id.present?

        raise ArgumentError, "Prompt #{record[:id].inspect} references a target that was not imported."
      end

      def normalize_status(raw_status)
        status = raw_status.to_s
        Prompt::ALLOWED_STATUSES.include?(status) ? status : "pending"
      end

      def upsert_rows(rows, unique_index)
        deduplicated_rows = rows.index_by do |row|
          [row[:search_id], row[:target_id], row[:full_query_text]]
        end.values

        Prompt.upsert_all(
          deduplicated_rows,
          unique_by: unique_index,
          on_duplicate: ON_DUPLICATE_SQL,
          # The backup rows already carry their source timestamps. Disabling
          # Rails timestamp injection also avoids a second updated_at assignment
          # alongside the explicit EXCLUDED.updated_at assignment above.
          record_timestamps: false
        )
      end
    end
  end
end
