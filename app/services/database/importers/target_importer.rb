# frozen_string_literal: true

module Database
  module Importers
    class TargetImporter < BaseImporter
      def call
        records.each { |record| import_record(record) }
      end

      private

      def import_record(record)
        category_id = mapped_id(:categories, record[:category_id])
        if category_id.blank?
          raise ArgumentError,
                "Target #{record[:id].inspect} references a category that was not imported."
        end

        domain = normalized_domain(record)
        target = Target.find_or_initialize_by(category_id: category_id, domain: domain)
        assign_target_attributes(target, record)
        target.save!
        imported_id_map(:targets, record[:id], target.id)
      end

      def normalized_domain(record)
        domain = Target.new(domain: record[:domain]).domain
        raise ArgumentError, "Target #{record[:id].inspect} has no valid domain." if domain.blank?

        domain
      end

      def assign_target_attributes(target, record)
        target.assign_attributes(
          name: record[:name],
          allow_query_strings: record[:allow_query_strings].nil? ? false : record[:allow_query_strings],
          is_active: record[:is_active].nil? || record[:is_active]
        )
        apply_timestamps(target, record)
      end
    end
  end
end
