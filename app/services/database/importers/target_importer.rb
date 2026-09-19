# frozen_string_literal: true

module Database
  module Importers
    class TargetImporter < BaseImporter
      def call
        records.each do |record|
          target = find_or_initialize_target(record["domain"])
          target.assign_attributes(target_attributes(record))
          target.save!

          id_maps["targets"][record["id"]] = target.id
        end
      end

      private

      def find_or_initialize_target(domain)
        Target.joins(:category)
              .where(categories: { user_id: target_user_id })
              .find_by(domain: domain) || Target.new(domain: domain)
      end

      def resolve_category_id(old_cat_id)
        return nil if old_cat_id.blank?

        new_cat_id = id_maps["categories"][old_cat_id]
        category = Category.find_by(id: new_cat_id, user_id: target_user_id) if new_cat_id.present?

        return category.id if category

        raise StandardError,
              "Category #{old_cat_id} (mapped to #{new_cat_id}) does not belong to user #{target_user_id}"
      end

      def target_attributes(record)
        category_id = resolve_category_id(record["category_id"])

        {
          name: record["name"],
          category_id: category_id.presence,
          allow_query_strings: record["allow_query_strings"],
          is_active: record["is_active"]
        }.compact
      end
    end
  end
end
