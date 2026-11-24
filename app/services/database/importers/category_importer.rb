# frozen_string_literal: true

module Database
  module Importers
    class CategoryImporter < BaseImporter
      def call
        records.each { |record| import_record(record) }
      end

      private

      def import_record(record)
        name = record[:name].to_s
        raise ArgumentError, "Category #{record[:id].inspect} has no name." if name.blank?

        updated_at = imported_timestamp(record[:updated_at])
        category = find_or_create_category(name, record, updated_at)
        category.update!(updated_at: updated_at) if record[:updated_at].present?
        imported_id_map(:categories, record[:id], category.id)
      end

      def find_or_create_category(name, record, updated_at)
        Category.find_or_create_by!(user_id: target_user_id, name: name) do |new_category|
          new_category.created_at = imported_timestamp(record[:created_at])
          new_category.updated_at = updated_at
        end
      end
    end
  end
end
