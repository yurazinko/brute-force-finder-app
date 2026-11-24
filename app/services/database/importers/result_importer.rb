# frozen_string_literal: true

module Database
  module Importers
    class ResultImporter < BaseImporter
      UNIQUE_INDEX = :index_results_on_search_id_and_url_hash
      PASSTHROUGH_FIELDS = %i[title content engine target_domain target_pattern].freeze

      def call
        rows = records.filter_map { |record| build_result_row(record) }
        return if rows.empty?

        # PostgreSQL rejects an ON CONFLICT batch that contains the same conflict
        # key more than once. Keep the last representation of each source result.
        deduplicated_rows = rows.index_by { |row| [row[:search_id], row[:url_hash]] }.values
        Result.upsert_all(deduplicated_rows, unique_by: UNIQUE_INDEX)
      end

      private

      def build_result_row(record)
        search_id = resolve_search_id(record)
        url = resolve_url(record)
        target_id = resolve_target_id(record)
        url_hash = resolve_url_hash(record, url)

        result_attributes(record, search_id: search_id, target_id: target_id, url: url, url_hash: url_hash)
      end

      def resolve_search_id(record)
        search_id = mapped_id(:searches, record[:search_id])
        return search_id if search_id.present?

        raise ArgumentError, "Result #{record[:id].inspect} references a search that was not imported."
      end

      def resolve_url(record)
        url = record[:url].to_s.strip
        raise ArgumentError, "Result #{record[:id].inspect} has no URL." if url.blank?

        url
      end

      def resolve_target_id(record)
        source_target_id = record[:target_id]
        return nil if source_target_id.blank?

        target_id = mapped_id(:targets, source_target_id)
        return target_id if target_id.present?

        raise ArgumentError, "Result #{record[:id].inspect} references a target that was not imported."
      end

      def resolve_url_hash(record, url)
        url_hash = record[:url_hash].presence || Utils::UrlNormalizer.hash(url)
        raise ArgumentError, "Result #{record[:id].inspect} has no usable URL hash." if url_hash.blank?

        url_hash
      end

      def result_attributes(record, search_id:, target_id:, url:, url_hash:)
        record.slice(*PASSTHROUGH_FIELDS).merge(
          search_id: search_id, target_id: target_id, url: url, url_hash: url_hash,
          **state_attributes(record), **timestamp_attributes(record)
        )
      end

      def state_attributes(record)
        {
          status: allowed_value(record[:status], Result::ALLOWED_STATUSES, "unread"),
          acknowledged: ActiveModel::Type::Boolean.new.cast(record[:acknowledged].presence || false),
          matched_keywords: Array(record[:matched_keywords]),
          relevance_score: record[:relevance_score].to_i,
          verification_status: allowed_value(
            record[:verification_status], Result::ALLOWED_VERIFICATION_STATUSES, "pending"
          )
        }
      end

      def timestamp_attributes(record)
        {
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
