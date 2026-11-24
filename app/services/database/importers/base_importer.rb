# frozen_string_literal: true

module Database
  module Importers
    class BaseImporter
      attr_reader :records, :target_user_id, :id_maps

      def initialize(records, target_user_id, id_maps)
        @records = Array(records).map.with_index do |record, index|
          raise ArgumentError, "Import record ##{index + 1} must be an object." unless record.is_a?(Hash)

          record.with_indifferent_access
        end
        @target_user_id = target_user_id
        @id_maps = id_maps
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      private

      def imported_id_map(map_name, source_id, target_id)
        return if source_id.blank?

        (id_maps[map_name] ||= {})[source_id.to_s] = target_id
      end

      def mapped_id(map_name, source_id)
        return if source_id.blank?

        id_maps.fetch(map_name, {})[source_id.to_s]
      end

      def imported_timestamp(value, fallback: Time.current)
        return fallback if value.blank?

        value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        raise ArgumentError, "Invalid timestamp in backup: #{value.inspect}"
      end

      def apply_timestamps(record, source)
        record.created_at = imported_timestamp(source[:created_at]) if record.new_record?
        record.updated_at = imported_timestamp(source[:updated_at]) if source[:updated_at].present?
      end
    end
  end
end
