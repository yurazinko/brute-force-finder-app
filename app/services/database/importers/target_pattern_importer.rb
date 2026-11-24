# frozen_string_literal: true

module Database
  module Importers
    class TargetPatternImporter < BaseImporter
      def call
        records.each do |record|
          target_id = mapped_id(:targets, record[:target_id])
          raise ArgumentError, "Target pattern #{record[:id].inspect} references a target that was not imported." if target_id.blank?

          pattern_value = record[:path_pattern].to_s.strip
          raise ArgumentError, "Target pattern #{record[:id].inspect} has no path pattern." if pattern_value.blank?
          pattern_value = "/#{pattern_value}" unless pattern_value.start_with?("/")

          pattern = TargetPattern.find_or_create_by!(target_id: target_id, path_pattern: pattern_value) do |new_pattern|
            new_pattern.is_active = record[:is_active].nil? ? true : record[:is_active]
            new_pattern.created_at = imported_timestamp(record[:created_at])
            new_pattern.updated_at = imported_timestamp(record[:updated_at])
          end
          pattern.update!(is_active: record[:is_active]) unless record[:is_active].nil? || pattern.is_active == record[:is_active]
          imported_id_map(:target_patterns, record[:id], pattern.id)
        end
      end
    end
  end
end
