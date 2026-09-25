# frozen_string_literal: true

module Results
  class Counters # rubocop:disable Metrics/ClassLength
    STATUSES = %w[unread watched interesting garbage].freeze

    Counts = Struct.new(
      :unread,
      :watched,
      :interesting,
      :garbage,
      :all_clean,
      :total,
      :has_less_relevant,
      keyword_init: true
    ) do
      def initialize(
        unread: 0,
        watched: 0,
        interesting: 0,
        garbage: 0,
        all_clean: nil,
        total: 0,
        has_less_relevant: false
      )
        all_clean ||= (unread.to_i + interesting.to_i + watched.to_i)
        super
      end
    end

    class << self
      def calculate_filtered(base_scope, options = {}, search = nil)
        normalized = options.to_h.symbolize_keys
        query = Results::Query.new(base_scope, normalized, search: search)
        scope = query.filtered_scope

        raw_counts = scope
                     .group(:status, :acknowledged, Arel.sql("results.relevance_score <= 0"))
                     .count

        build_counts_from_raw(
          raw_counts,
          normalized,
          search_acknowledged: query.show_acknowledged?
        )
      end

      def bulk_calculate(searches, options = {})
        search_ids = searches.map(&:id)
        return {} if search_ids.empty?

        normalized = options.to_h.symbolize_keys
        raw_data = fetch_bulk_raw_data(search_ids, normalized)
        ack_map = searches.to_h { |search| [search.id, search.show_acknowledged?] }
        grouped_data = group_by_search_id(raw_data)

        search_ids.index_with do |search_id|
          search_raw = grouped_data.fetch(search_id, {})
          build_counts_from_raw(
            search_raw,
            normalized,
            search_acknowledged: ack_map.fetch(search_id, false)
          )
        end
      end

      private

      def build_counts_from_raw(raw_counts, options, search_acknowledged: false)
        allowed_ack = search_acknowledged_values(options, search_acknowledged)
        target_status = options[:status].presence || "unread"
        show_irrelevant = boolean(options[:show_less_relevant])

        has_less_relevant = check_less_relevant(raw_counts, target_status, allowed_ack)
        status_sums = calculate_status_sums(raw_counts, show_irrelevant, allowed_ack)

        build_counts(
          status_sums.merge(
            total: raw_counts.values.sum,
            has_less_relevant: has_less_relevant
          )
        )
      end

      def calculate_status_sums(raw_counts, show_irrelevant, allowed_ack)
        STATUSES.index_with do |status|
          sum_status(raw_counts, status, show_irrelevant, allowed_ack)
        end.symbolize_keys
      end

      def build_counts(attributes)
        Counts.new(**attributes)
      end

      def empty_status_counts
        STATUSES.index_with { 0 }.symbolize_keys
      end

      def search_acknowledged_values(options, search_acknowledged)
        if options[:show_acknowledged].nil?
          search_acknowledged ? [false, true] : [false]
        else
          boolean(options[:show_acknowledged]) ? [false, true] : [false]
        end
      end

      def check_less_relevant(raw_counts, target_status, allowed_ack)
        raw_counts.any? do |(status, ack, is_less), count|
          next false unless filter_entry?(status, ack, target_status, allowed_ack)

          boolean(is_less) && count.positive?
        end
      end

      def sum_status(raw_counts, current_status, show_irrelevant, allowed_ack)
        raw_counts.sum do |(status, ack, is_less), count|
          next 0 unless status.to_s == current_status.to_s

          next 0 if current_status.to_s == "unread" && allowed_ack.exclude?(ack)

          next 0 if !show_irrelevant && boolean(is_less)

          count
        end
      end

      def filter_entry?(status, ack, target_status, allowed_ack)
        return false unless status.to_s == target_status.to_s
        return true unless target_status.to_s == "unread"

        allowed_ack.include?(ack)
      end

      def group_by_search_id(raw_data)
        raw_data.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((search_id, *key), count), grouped|
          grouped[search_id][key] = count
        end
      end

      def fetch_bulk_raw_data(search_ids, options)
        query = Results::Query.new(Result.where(search_id: search_ids), options)

        query.filtered_scope
             .group(
               :search_id,
               :status,
               :acknowledged,
               Arel.sql("results.relevance_score <= 0")
             )
             .count
      end

      def boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
