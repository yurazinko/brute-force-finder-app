# frozen_string_literal: true

module Database
  module Importers
    class CategoryImporter < BaseImporter
      def call
        records.each do |record|
          category = Category.find_or_create_by!(user_id: target_user_id, name: record["name"]) do |cat|
            cat.created_at = record["created_at"]
            cat.updated_at = record["updated_at"]
          end

          id_maps["categories"][record["id"]] = category.id
        end
      end
    end
  end
end
