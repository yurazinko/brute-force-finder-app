# frozen_string_literal: true

module Database
  module Importers
    class TargetImporter < BaseImporter
      def call
        records.each do |record|
          category_id = mapped_id(:categories, record[:category_id])
          raise ArgumentError, "Target #{record[:id].inspect} references a category that was not imported." if category_id.blank?

          normalized_domain = Target.new(domain: record[:domain]).domain
          raise ArgumentError, "Target #{record[:id].inspect} has no valid domain." if normalized_domain.blank?

          target = Target.find_or_initialize_by(category_id: category_id, domain: normalized_domain)
          target.assign_attributes(
            name: record[:name],
            allow_query_strings: record[:allow_query_strings].nil? ? false : record[:allow_query_strings],
            is_active: record[:is_active].nil? ? true : record[:is_active]
          )
          apply_timestamps(target, record)
          target.save!
          imported_id_map(:targets, record[:id], target.id)
        end
      end
    end
  end
end
