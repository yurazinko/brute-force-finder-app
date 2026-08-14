# frozen_string_literal: true

module Database
  module Importers
    class SearchImporter < BaseImporter
      def call
        records.each do |record|
          search = Search.create!(
            user_id: target_user_id,
            title: record["title"],
            query_conditions: record["query_conditions"],
            show_acknowledged: record["show_acknowledged"] || false,
            status: record["status"] || "pending",
            time_frame: record["time_frame"],
            created_at: record["created_at"],
            updated_at: record["updated_at"]
          )
          id_maps["searches"][record["id"]] = search.id
        end
      end
    end
  end
end
