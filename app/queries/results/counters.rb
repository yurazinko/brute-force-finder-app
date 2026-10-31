# frozen_string_literal: true

module Results
  class Counters
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

        raw_counts = if search.nil?
                       global_feed_raw_counts(scope)
                     else
                       scope
                         .group("results.status", "results.acknowledged", less_relevant_condition(search))
                         .count
                     end

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
        ack_map = searches.to_h { |search| [search.id, search.show_acknowledged?] }

        raw_data = fetch_bulk_raw_data(search_ids, normalized)
        grouped_data = group_by_search_id(raw_data)

        search_ids.index_with do |search_id|
          search_raw = grouped_data.fetch(search_id, {})
          build_counts_from_raw(
            search_raw,
            normalized,
            search_acknowledged: ack_map.fetch(search_id, false),
            global_feed: false
          )
        end
      end

      private

      def build_counts_from_raw(raw_counts, options, search_acknowledged: false, global_feed: false)
        allowed_ack = search_acknowledged_values(options, search_acknowledged)
        target_status = options[:status].presence || "unread"
        # Missing query parameter must behave exactly like false.
        show_irrelevant = ActiveModel::Type::Boolean.new.cast(options[:show_less_relevant]) == true

        has_less_relevant = check_less_relevant(raw_counts, target_status, allowed_ack)
        status_sums = calculate_status_sums(raw_counts, show_irrelevant, allowed_ack, global_feed)

        build_counts(
          status_sums.merge(
            total: raw_counts.values.sum,
            has_less_relevant: has_less_relevant
          )
        )
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
          next 0 unless status.to_s == current_status.to_s
          next 0 if current_status.to_s == "unread" && allowed_ack.exclude?(boolean(ack))

          less_relevant = boolean(is_less)

          if global_feed
            # A global feed combines searches with different thresholds, so its
            # counters must follow the currently selected relevance bucket.
            next 0 unless less_relevant == show_irrelevant
          elsif !show_irrelevant && less_relevant
            # On a campaign page, show_less_relevant expands the tab counters
            # to include partial/less-relevant records alongside relevant ones.
            next 0
          end

          count
        end
      end

      def filter_entry?(status, ack, target_status, allowed_ack)
        return false unless status.to_s == target_status.to_s
        return true unless target_status.to_s == "unread"

        allowed_ack.include?(boolean(ack))
      end

      # A global feed can contain searches with different relevance modes.
      # Group by the raw score and parent mode, then classify each group in Ruby.
      # This avoids relying on a nested CASE expression as a GROUP BY key, whose
      # adapter-specific result type can otherwise be misread by boolean().
      def global_feed_raw_counts(scope)
        grouped = scope
                  .joins(:search)
                  .group(
                    "results.search_id",
                    "searches.relevance_mode",
                    "results.status",
                    "results.acknowledged",
                    "results.relevance_score"
                  )
                  .count

        grouped.each_with_object(Hash.new(0)) do |((_search_id, relevance_mode, status, acknowledged, score), count), result|
          less_relevant = less_relevant_score?(score, relevance_mode)
          result[[status, acknowledged, less_relevant]] += count
        end
      end

      def less_relevant_score?(score, relevance_mode)
        return false if score.nil?

        if relevance_mode.to_s == "strict"
          score < RelevanceRanker::MAX_SCORE
        else
          score <= 0
        end
      end

      def group_by_search_id(raw_data)
        raw_data.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((search_id, *key), count), grouped|
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
        if search&.strict_mode?
          Arel.sql("CASE WHEN results.relevance_score < #{RelevanceRanker::MAX_SCORE} THEN 1 ELSE 0 END")
        elsif search
          Arel.sql("CASE WHEN results.relevance_score <= 0 THEN 1 ELSE 0 END")
        else
          Arel.sql(
            "CASE WHEN searches.relevance_mode = 'strict' THEN " \
            "CASE WHEN results.relevance_score < #{RelevanceRanker::MAX_SCORE} THEN 1 ELSE 0 END " \
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
