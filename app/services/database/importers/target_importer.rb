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

        old_cat_id = record["category_id"]
        new_cat_id = id_maps["categories"][old_cat_id]

        if new_cat_id.present?
          category = Category.find_by(id: new_cat_id, user_id: target_user_id)
          raise "Category #{new_cat_id} does not belong to user #{target_user_id}" unless category

          attrs[:category_id] = category.id
        end

        attrs
      end
    end
  end
end
