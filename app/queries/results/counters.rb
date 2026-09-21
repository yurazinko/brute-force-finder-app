# frozen_string_literal: true

module Results
  class Counters
    extend FilterableContext

    STATUSES = %w[unread watched interesting garbage].freeze

    Counts = Struct.new(:unread, :watched, :interesting, :garbage, :has_less_relevant, keyword_init: true) do
      def initialize(unread: 0, watched: 0, interesting: 0, garbage: 0, has_less_relevant: false)
        super
      end
    end

    class << self
      def calculate(base_scope)
        raw_counts = base_scope.group(:status).count

        Counts.new(
          unread: raw_counts.fetch("unread", 0),
          watched: raw_counts.fetch("watched", 0),
          interesting: raw_counts.fetch("interesting", 0),
          garbage: raw_counts.fetch("garbage", 0)
        )
      end

      def calculate_filtered(base_scope, options = {}, search = nil)
        normalized = options.to_h.symbolize_keys
        scope = apply_base_filters_without_relevance(base_scope, normalized)

        raw_counts = scope.group(:status, :acknowledged, Arel.sql("results.relevance_score <= 0")).count
        search_ack = search_show_acknowledged_status(search)

        build_counts_from_raw(raw_counts, normalized, search_ack)
      end

      def bulk_calculate(searches, options = {})
        search_ids = searches.map(&:id)
        return {} if search_ids.empty?

        normalized = options.to_h.symbolize_keys
        raw_data = fetch_bulk_raw_data(search_ids, normalized)
        ack_map = build_search_acknowledged_map(searches)

        search_ids.index_with do |search_id|
          build_counts_for_search(search_id, raw_data, normalized, ack_map[search_id])
        end
      end

      private

      def apply_base_filters_without_relevance(scope, options)
        scope = scope.by_time_frame(options[:time_frame]) if options[:time_frame].present?
        scope = scope.search_by_keyword(options[:keyword]) if options[:keyword].present?
        scope
      end

      def search_show_acknowledged_status(search)
        search.respond_to?(:show_acknowledged) ? cast_boolean(search.show_acknowledged) : false
      end

      def build_search_acknowledged_map(searches)
        searches.to_h { |search| [search.id, search_show_acknowledged_status(search)] }
      end

      def build_counts_from_raw(raw_counts, options, search_ack)
        allowed_ack = unread_acknowledged_conditions(options, search_show_acknowledged: search_ack)
        target_status = options[:status].presence || "unread"
        show_irrelevant = cast_boolean(options[:show_less_relevant])

        has_less_relevant = check_less_relevant(raw_counts, target_status, allowed_ack)
        status_sums = STATUSES.index_with do |status|
          sum_status(raw_counts, status, show_irrelevant, allowed_ack)
        end

        Counts.new(**status_sums.symbolize_keys, has_less_relevant: has_less_relevant)
      end

      def build_counts_for_search(search_id, raw_data, options, search_ack)
        search_raw = raw_data.select { |(s_id, *), _| s_id == search_id }
                             .transform_keys { |(_, *key)| key }

        build_counts_from_raw(search_raw, options, search_ack)
      end

      def check_less_relevant(raw_counts, target_status, allowed_ack)
        raw_counts.any? do |(status, ack, is_less), count|
          next false unless filter_entry?(status, ack, target_status, allowed_ack)

          cast_boolean(is_less) && count.positive?
        end
      end

      def sum_status(raw_counts, target_status, show_irrelevant, allowed_ack)
        raw_counts.sum do |(status, ack, is_less), count|
          next 0 unless filter_entry?(status, ack, target_status, allowed_ack)
          next 0 unless included_by_relevance?(is_less, show_irrelevant)

          count
        end
      end

      def filter_entry?(status, ack, target_status, allowed_ack)
        return false unless status.to_s == target_status.to_s
        return true unless target_status.to_s == "unread" && allowed_ack.present?

        allowed_ack.include?(ack)
      end

      def included_by_relevance?(is_less, show_irrelevant)
        show_irrelevant || !cast_boolean(is_less)
      end

      def fetch_bulk_raw_data(search_ids, options)
        scope = Result.where(search_id: search_ids)
        scope = apply_base_filters_without_relevance(scope, options)
        scope.group(:search_id, :status, :acknowledged, Arel.sql("results.relevance_score <= 0")).count
      end
    end
  end
end
