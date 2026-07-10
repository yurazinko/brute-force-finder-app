# frozen_string_literal: true

module Results
  class Counters
    extend FilterableContext

    Counts = Struct.new(:unread, :watched, :interesting, :garbage)

    class << self
      def calculate(base_scope)
        raw_counts = base_scope.group(:status).count

        Counts.new(
          base_scope.where(status: "unread").count,
          raw_counts.fetch("watched", 0),
          raw_counts.fetch("interesting", 0),
          raw_counts.fetch("garbage", 0)
        )
      end

      def calculate_filtered(base_scope, options = {}, search = nil)
        normalized_options = options.to_h.symbolize_keys
        filtered_base = apply_base_filters(base_scope, normalized_options)

        raw_counts = filtered_base.group(:status, :acknowledged).count
        search_acknowledged = search_show_acknowledged_status(search)

        build_counts_from_raw(raw_counts, normalized_options, search_acknowledged)
      end

      def bulk_calculate(searches, options = {})
        search_ids = searches.map(&:id)
        return {} if search_ids.empty?

        normalized_options = options.to_h.symbolize_keys
        raw_data = fetch_bulk_raw_data(search_ids, normalized_options)
        search_acknowledged_map = build_search_acknowledged_map(searches)

        search_ids.index_with do |search_id|
          build_counts_for_search(search_id, raw_data, normalized_options, search_acknowledged_map[search_id])
        end
      end

      private

      def apply_base_filters(scope, options)
        scope = scope.by_time_frame(options[:time_frame])
        options[:keyword].present? ? scope.search_by_keyword(options[:keyword]) : scope
      end

      def search_show_acknowledged_status(search)
        search.respond_to?(:show_acknowledged) ? cast_boolean(search.show_acknowledged) : false
      end

      def build_search_acknowledged_map(searches)
        searches.to_h do |search|
          [search.id, search_show_acknowledged_status(search)]
        end
      end

      def build_counts_from_raw(raw_counts, options, search_acknowledged)
        allowed_unread_acknowledged =
          unread_acknowledged_conditions(options, search_show_acknowledged: search_acknowledged)

        Counts.new(
          sum_status_from_raw(raw_counts, "unread", allowed_unread_acknowledged),
          sum_status_from_raw(raw_counts, "watched"),
          sum_status_from_raw(raw_counts, "interesting"),
          sum_status_from_raw(raw_counts, "garbage")
        )
      end

      def sum_status_from_raw(raw_counts, target_status, allowed_acknowledged = nil)
        raw_counts.sum do |(status, acknowledged), count|
          next 0 unless status == target_status
          next 0 if allowed_acknowledged&.exclude?(acknowledged)

          count
        end
      end

      def fetch_bulk_raw_data(search_ids, options)
        scope = Result.where(search_id: search_ids)
        apply_base_filters(scope, options).group(:search_id, :status, :acknowledged).count
      end

      def build_counts_for_search(search_id, raw_data, options, search_acknowledged)
        allowed_unread_acknowledged =
          unread_acknowledged_conditions(options, search_show_acknowledged: search_acknowledged)

        Counts.new(
          sum_bulk_status(raw_data, search_id, "unread", allowed_unread_acknowledged),
          sum_bulk_status(raw_data, search_id, "watched"),
          sum_bulk_status(raw_data, search_id, "interesting"),
          sum_bulk_status(raw_data, search_id, "garbage")
        )
      end

      def sum_bulk_status(raw_data, target_search_id, target_status, allowed_acknowledged = nil)
        raw_data.sum do |(search_id, result_status, acknowledged), count|
          next 0 unless search_id == target_search_id && result_status == target_status
          next 0 if allowed_acknowledged&.exclude?(acknowledged)

          count
        end
      end
    end
  end
end
