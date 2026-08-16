# frozen_string_literal: true

module Database
  module Importers
    class PromptImporter < BaseImporter
      def call
        prompts = records.filter_map { |r| build_prompt_row(r) }
        Prompt.insert_all(prompts) if prompts.any?
      end

      private

      def build_prompt_row(record)
        search_id = id_maps["searches"][record["search_id"]]
        query_text = record["full_query_text"]

        return if search_id.blank? || query_text.blank?

        {
          search_id: search_id,
          target_id: id_maps["targets"][record["target_id"]],
          full_query_text: query_text,
          status: record["status"] || "pending",
          error_message: record["error_message"],
          created_at: Time.zone.parse(record["created_at"]),
          updated_at: Time.zone.parse(record["updated_at"])
        }
      end
    end
  end
end
