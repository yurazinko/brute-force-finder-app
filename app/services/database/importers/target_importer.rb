# frozen_string_literal: true

module Database
  module Importers
    class TargetImporter < BaseImporter
      def call
        records.each do |record|
          target = Target.find_or_initialize_by(domain: record["domain"])
          target.assign_attributes(target_attributes(record))
          target.save!

          id_maps["targets"][record["id"]] = target.id
        end
      end

      private

      def target_attributes(record)
        attrs = { name: record["name"] }
        attrs[:allow_query_strings] = record["allow_query_strings"] if record.key?("allow_query_strings")
        attrs[:is_active] = record["is_active"] if record.key?("is_active")

        new_cat_id = id_maps["categories"][record["category_id"]]
        attrs[:category_id] = new_cat_id if new_cat_id.present?
        attrs
      end
    end
  end
end
