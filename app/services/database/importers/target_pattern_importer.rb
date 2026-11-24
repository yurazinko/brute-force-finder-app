# frozen_string_literal: true

module Database
  module Importers
    class TargetPatternImporter < BaseImporter
      def call
        records.each { |record| import_record(record) }
      end

      private

      def import_record(record)
        target_id = mapped_id(:targets, record[:target_id])
        if target_id.blank?
          raise ArgumentError,
                "Target pattern #{record[:id].inspect} references a target that was not imported."
        end

        pattern_value = normalized_path_pattern(record)
        pattern = find_or_create_pattern(target_id, pattern_value, record)
        sync_active_flag(pattern, record[:is_active])
        imported_id_map(:target_patterns, record[:id], pattern.id)
      end

      def normalized_path_pattern(record)
        value = record[:path_pattern].to_s.strip
        raise ArgumentError, "Target pattern #{record[:id].inspect} has no path pattern." if value.blank?

        value.start_with?("/") ? value : "/#{value}"
      end

      def find_or_create_pattern(target_id, pattern_value, record)
        TargetPattern.find_or_create_by!(target_id: target_id, path_pattern: pattern_value) do |new_pattern|
          new_pattern.is_active = record[:is_active].nil? || record[:is_active]
          new_pattern.created_at = imported_timestamp(record[:created_at])
          new_pattern.updated_at = imported_timestamp(record[:updated_at])
        end
      end

      def sync_active_flag(pattern, is_active)
        return if is_active.nil? || pattern.is_active == is_active

        pattern.update!(is_active: is_active)
      end
    end
  end
end
