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
        search_id = mapped_id(:searches, record[:search_id])
        raise ArgumentError, "Prompt #{record[:id].inspect} references a search that was not imported." if search_id.blank?
        raise ArgumentError, "Prompt #{record[:id].inspect} has no query text." if record[:full_query_text].blank?

        source_target_id = record[:target_id]
        target_id = mapped_id(:targets, source_target_id) if source_target_id.present?
        if source_target_id.present? && target_id.blank?
          raise ArgumentError, "Prompt #{record[:id].inspect} references a target that was not imported."
        end

        status = Prompt::ALLOWED_STATUSES.include?(record[:status].to_s) ? record[:status].to_s : "pending"
        {
          search_id: search_id,
          target_id: target_id,
          full_query_text: record[:full_query_text],
          status: status,
          error_message: record[:error_message],
          created_at: imported_timestamp(record[:created_at]),
          updated_at: imported_timestamp(record[:updated_at])
        }
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
