# frozen_string_literal: true

module Database
  module Importers
    class ResultImporter < BaseImporter
      UNIQUE_INDEX = :index_results_on_search_id_and_url_hash

      def call
        rows = records.filter_map { |record| build_result_row(record) }
        return if rows.empty?

        # PostgreSQL rejects an ON CONFLICT batch that contains the same conflict
        # key more than once. Keep the last representation of each source result.
        deduplicated_rows = rows.index_by { |row| [row[:search_id], row[:url_hash]] }.values
        Result.upsert_all(deduplicated_rows, unique_by: UNIQUE_INDEX)
      end

      private

      def build_result_row(record) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        search_id = mapped_id(:searches, record[:search_id])
        raise ArgumentError, "Result #{record[:id].inspect} references a search that was not imported." if search_id.blank?

        url = record[:url].to_s.strip
        raise ArgumentError, "Result #{record[:id].inspect} has no URL." if url.blank?

        source_target_id = record[:target_id]
        target_id = mapped_id(:targets, source_target_id) if source_target_id.present?
        if source_target_id.present? && target_id.blank?
          raise ArgumentError, "Result #{record[:id].inspect} references a target that was not imported."
        end

        url_hash = record[:url_hash].presence || Utils::UrlNormalizer.hash(url)
        raise ArgumentError, "Result #{record[:id].inspect} has no usable URL hash." if url_hash.blank?

        {
          search_id: search_id,
          target_id: target_id,
          title: record[:title],
          url: url,
          url_hash: url_hash,
          content: record[:content],
          engine: record[:engine],
          status: allowed_value(record[:status], Result::ALLOWED_STATUSES, "unread"),
          acknowledged: record[:acknowledged].nil? ? false : ActiveModel::Type::Boolean.new.cast(record[:acknowledged]),
          target_domain: record[:target_domain],
          target_pattern: record[:target_pattern],
          matched_keywords: Array(record[:matched_keywords]),
          relevance_score: record[:relevance_score].to_i,
          verification_status: allowed_value(
            record[:verification_status], Result::ALLOWED_VERIFICATION_STATUSES, "pending"
          ),
          viewed_at: record[:viewed_at].present? ? imported_timestamp(record[:viewed_at]) : nil,
          created_at: imported_timestamp(record[:created_at]),
          updated_at: imported_timestamp(record[:updated_at])
        }
      end

      def allowed_value(value, allowed_values, fallback)
        candidate = value.to_s
        allowed_values.include?(candidate) ? candidate : fallback
      end
    end
  end
end
