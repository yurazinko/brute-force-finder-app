# frozen_string_literal: true

module Results
  class Counters
    STATUSES = %w[unread watched interesting garbage].freeze

    Counts = Struct.new(
      :unread, :watched, :interesting, :garbage, :all_clean, :total, :has_less_relevant, keyword_init: true
    ) do
      def initialize(
        unread: 0, watched: 0, interesting: 0, garbage: 0, all_clean: nil, total: 0, has_less_relevant: false
      )
        all_clean ||= (unread.to_i + interesting.to_i + watched.to_i)
        super
      end
    end

    class << self
      def calculate_filtered(base_scope, options = {}, search = nil)
        normalized = options.to_h.symbolize_keys
        query = Results::Query.new(base_scope, normalized, search: search)
        raw_counts = fetch_raw_counts(query.filtered_scope, search)

        build_counts_from_raw(
          raw_counts,
          normalized,
          search_acknowledged: query.show_acknowledged?,
          global_feed: search.nil?
        )
      end

      def bulk_calculate(searches, options = {})
        search_ids = searches.map(&:id)
        return {} if search_ids.empty?

        normalized = options.to_h.symbolize_keys
        ack_map = searches.to_h { |s| [s.id, s.show_acknowledged?] }
        grouped_data = group_by_search_id(fetch_bulk_raw_data(search_ids, normalized))

        search_ids.index_with do |search_id|
          build_counts_from_raw(
            grouped_data.fetch(search_id, {}),
            normalized,
            search_acknowledged: ack_map.fetch(search_id, false),
            global_feed: false
          )
        end
      end

      private

      def fetch_raw_counts(scope, search)
        if search.nil?
          global_feed_raw_counts(scope)
        else
          scope.group("results.status", "results.acknowledged", less_relevant_condition(search)).count
        end
      end

      def build_counts_from_raw(raw_counts, options, search_acknowledged: false, global_feed: false)
        allowed_ack = search_acknowledged_values(options, search_acknowledged)
        target_status = options[:status].presence || "unread"
        show_irrelevant = ActiveModel::Type::Boolean.new.cast(options[:show_less_relevant]) == true

        has_less_relevant = check_less_relevant(raw_counts, target_status, allowed_ack)
        status_sums = calculate_status_sums(raw_counts, show_irrelevant, allowed_ack, global_feed)

        build_counts(status_sums.merge(total: raw_counts.values.sum, has_less_relevant: has_less_relevant))
      end

      def calculate_status_sums(raw_counts, show_irrelevant, allowed_ack, global_feed)
        STATUSES.index_with do |status|
          sum_status(raw_counts, status, show_irrelevant, allowed_ack, global_feed)
        end.symbolize_keys
      end

      def build_counts(attributes)
        Counts.new(**attributes)
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

      def sum_status(raw_counts, current_status, show_irrelevant, allowed_ack, global_feed)
        raw_counts.sum do |(status, ack, is_less), count|
          next 0 unless valid_status_entry?(status, current_status)
          next 0 if current_status.to_s == "unread" && allowed_ack.exclude?(boolean(ack))

          less_relevant = boolean(is_less)
          next 0 unless valid_relevance_inclusion?(less_relevant, show_irrelevant, global_feed)

          count
        end
      end

      def valid_status_entry?(status, current_status)
        status.to_s == current_status.to_s
      end

      def valid_relevance_inclusion?(less_relevant, show_irrelevant, global_feed)
        if global_feed
          less_relevant == show_irrelevant
        elsif !show_irrelevant && less_relevant
          false
        else
          true
        end
      end

      def filter_entry?(status, ack, target_status, allowed_ack)
        return false unless status.to_s == target_status.to_s
        return true unless target_status.to_s == "unread"

        allowed_ack.include?(boolean(ack))
      end

      def global_feed_raw_counts(scope)
        grouped = scope.joins(:search).group(
          "results.search_id", "searches.relevance_mode",
          "results.status", "results.acknowledged", "results.relevance_score"
        ).count

        grouped.each_with_object(Hash.new(0)) do |((_, mode, status, ack, score), count), result|
          result[[status, ack, less_relevant_score?(score, mode)]] += count
        end
      end

      def less_relevant_score?(score, relevance_mode)
        return false if score.nil?

        relevance_mode.to_s == "strict" ? score < RelevanceRanker::MAX_SCORE : score <= 0
      end

      def group_by_search_id(raw_data)
        raw_data.each_with_object(Hash.new { |h, k| h[k] = {} }) do |((search_id, *key), count), grouped|
          grouped[search_id][key] = count
        end
      end

      def fetch_bulk_raw_data(search_ids, options)
        query = Results::Query.new(Result.where(search_id: search_ids), options)
        query.filtered_scope
             .joins(:search)
             .group(:search_id, "results.status", "results.acknowledged", less_relevant_condition(nil))
             .count
      end

      def less_relevant_condition(search)
        max_score = RelevanceRanker::MAX_SCORE
        if search&.strict_mode?
          Arel.sql("CASE WHEN results.relevance_score < #{max_score} THEN 1 ELSE 0 END")
        elsif search
          Arel.sql("CASE WHEN results.relevance_score <= 0 THEN 1 ELSE 0 END")
        else
          Arel.sql(
            "CASE WHEN searches.relevance_mode = 'strict' THEN " \
            "CASE WHEN results.relevance_score < #{max_score} THEN 1 ELSE 0 END " \
            "ELSE CASE WHEN results.relevance_score <= 0 THEN 1 ELSE 0 END END"
          )
        end
      end

      def boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
