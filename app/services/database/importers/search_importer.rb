# frozen_string_literal: true

module Database
  module Importers
    class SearchImporter < BaseImporter
      def call
        records.each do |record|
          raw_query_conditions = record[:query_conditions]
          query_conditions = if raw_query_conditions.is_a?(String)
                               raw_query_conditions
                             else
                               JSON.generate(raw_query_conditions)
                             end
          created_at = imported_timestamp(record[:created_at], fallback: nil)
          search = find_existing_search(record, query_conditions, created_at) || Search.new(user_id: target_user_id)

          search.assign_attributes(
            title: record[:title],
            query_conditions: query_conditions,
            show_acknowledged: record[:show_acknowledged].nil? ? false : ActiveModel::Type::Boolean.new.cast(record[:show_acknowledged]),
            status: allowed_value(record[:status], Search::ALLOWED_STATUSES, "pending"),
            time_frame: allowed_value(record[:time_frame], Search::ALLOWED_TIME_FRAMES, nil),
            relevance_mode: allowed_value(
              record[:relevance_mode], Search::ALLOWED_RELEVANCE_MODES, Search::DEFAULT_RELEVANCE_MODE
            )
          )
          apply_timestamps(search, record)
          search.save!
          imported_id_map(:searches, record[:id], search.id)
        end
      end

      private

      def find_existing_search(record, query_conditions, created_at)
        return unless created_at

        scope = Search.where(
          user_id: target_user_id,
          title: record[:title],
          query_conditions: query_conditions,
          created_at: created_at...(created_at + 0.001)
        )
        scope.order(:id).first
      end

      def allowed_value(value, allowed_values, fallback)
        candidate = value.presence
        allowed_values.include?(candidate) ? candidate : fallback
      end
    end
  end
end
