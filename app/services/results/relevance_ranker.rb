# frozen_string_literal: true

module Results
  class RelevanceRanker
    RankResult = Struct.new(
      :relevance_score,
      :matched_keywords,
      :verification_status,
      :published_at,
      :valid?,
      keyword_init: true
    )

    POINTS_PER_MATCHED_GROUP = 100
    FIRST_GROUP_PENALTY = 250
    UNVERIFIED_PENALTY = 50
    UNKNOWN_DATE_PENALTY = 30

    def self.call(result, snippet_text, keyword_groups, url, time_range: nil)
      new(result, snippet_text, keyword_groups, url, time_range).call
    end

    def initialize(result, snippet_text, keyword_groups, url, time_range)
      @result = result
      @snippet_text = snippet_text.to_s
      @keyword_groups = keyword_groups || []
      @url = url
      @time_range = time_range
    end

    def call
      return build_rank([], "verified") if @keyword_groups.empty?

      snippet_eval = evaluate_text(@snippet_text)

      return build_rank(snippet_eval[:matched_keywords], "verified") if snippet_eval[:all_matched] && @time_range.blank?

      process_page_fetch(snippet_eval)
    end

    private

    def process_page_fetch(snippet_eval)
      fetch_res = PageFetcher.fetch(@url)

      if fetch_res.status == :verified
        published_at = DateExtractor.extract(fetch_res.text, fetch_res.headers)

        if outdated?(published_at)
          return RankResult.new(
            relevance_score: 0,
            matched_keywords: snippet_eval[:matched_keywords],
            verification_status: "outdated",
            published_at: published_at,
            valid?: false
          )
        end

        page_eval = evaluate_text(fetch_res.text)
        merged_kws = (snippet_eval[:matched_keywords] + page_eval[:matched_keywords]).uniq

        build_rank(merged_kws, "verified", published_at: published_at)
      else
        status = fetch_res.captcha_detected? ? "unverified_captcha" : "unverified_error"
        build_rank(snippet_eval[:matched_keywords], status, unverified: true)
      end
    end

    def outdated?(published_at)
      return false if published_at.nil? || cutoff_date.nil?

      published_at < cutoff_date
    end

    def cutoff_date
      @cutoff_date ||= case @time_range&.to_sym
                       when :day   then 1.day.ago
                       when :week  then 1.week.ago
                       when :month then 1.month.ago
                       when :year  then 1.year.ago
                       end
    end

    def evaluate_text(text)
      downcased = text.downcase
      matched_kws = @keyword_groups.filter_map do |group|
        group.find { |kw| downcased.include?(kw.downcase) }
      end

      {
        matched_keywords: matched_kws,
        all_matched: matched_kws.size == @keyword_groups.size
      }
    end

    def build_rank(matched_kws, status, unverified: false, published_at: nil)
      matched_groups_count = count_matched_groups(matched_kws)
      score = calculate_score(matched_groups_count, matched_kws, unverified, published_at)

      RankResult.new(
        relevance_score: score,
        matched_keywords: matched_kws,
        verification_status: status,
        published_at: published_at,
        valid?: @keyword_groups.empty? || matched_groups_count.positive?
      )
    end

    def count_matched_groups(matched_kws)
      downcased_kws = matched_kws.map(&:downcase)
      @keyword_groups.count { |group| group.any? { |kw| downcased_kws.include?(kw.downcase) } }
    end

    def calculate_score(matched_groups_count, matched_kws, unverified, published_at)
      return 0 if @keyword_groups.empty?

      downcased_kws = matched_kws.map(&:downcase)
      first_matched = @keyword_groups.first&.any? { |kw| downcased_kws.include?(kw.downcase) }

      score = matched_groups_count * POINTS_PER_MATCHED_GROUP
      score -= FIRST_GROUP_PENALTY unless first_matched
      score -= UNVERIFIED_PENALTY if unverified

      score -= UNKNOWN_DATE_PENALTY if @time_range.present? && published_at.nil?

      score
    end
  end
end
