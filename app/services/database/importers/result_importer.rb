# frozen_string_literal: true

module Database
  module Importers
    class ResultImporter < BaseImporter
      def call
        results = records.filter_map { |record| build_result_row(record) }
        Result.upsert_all(results, unique_by: %i[search_id url_hash]) if results.any?
      end

      private

      def build_result_row(record) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        search_id = id_maps[:searches][record[:search_id]]
        return if search_id.blank?

        {
          search_id: search_id,
          title: record[:title],
          url: record[:url],
          url_hash: record[:url_hash],
          content: record[:content],
          engine: record[:engine],
          status: record[:status] || "unread",
          acknowledged: record[:acknowledged] || false,
          target_domain: record[:target_domain],
          target_pattern: record[:target_pattern],
          matched_keywords: record[:matched_keywords] || [],
          relevance_score: record[:relevance_score] || 0,
          viewed_at: record[:viewed_at],
          created_at: Time.zone.parse(record[:created_at]),
          updated_at: Time.zone.parse(record[:updated_at])
        }
      end
    end
  end
end
