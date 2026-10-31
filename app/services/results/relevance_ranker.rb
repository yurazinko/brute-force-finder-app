# frozen_string_literal: true

module Results
  class RelevanceRanker
    RankResult = Struct.new(
      :relevance_score,
      :matched_keywords,
      :verification_status,
      :valid?,
      keyword_init: true
    )

    MAX_SCORE = 100
    FIRST_GROUP_PENALTY = 150
    CAPTCHA_SCORE_FLOOR = 25

    def self.call(result, snippet_text, keyword_groups, url, strict_mode: nil)
      new(result, snippet_text, keyword_groups, url, strict_mode: strict_mode).call
    end

    def self.matched_group_flags(matched_keywords, keyword_groups)
      normalized_matches = Array(matched_keywords).map { |keyword| normalize_keyword(keyword) }
      Array(keyword_groups).map do |group|
        Array(group).any? { |keyword| normalized_matches.include?(normalize_keyword(keyword)) }
      end
    end

    def self.first_group_matched?(matched_keywords, keyword_groups)
      matched_group_flags(matched_keywords, keyword_groups).first == true
    end

    # A CAPTCHA blocks full-page verification. Keep a score floor only when the
    # result has at least the primary signal; in balanced mode it must also have
    # one later-group signal so the exception cannot bypass that mode's rule.
    def self.captcha_candidate?(matched_keywords, keyword_groups, strict_mode:)
      groups = Array(keyword_groups)
      flags = matched_group_flags(matched_keywords, groups)
      return false unless flags.first

      strict_mode || groups.one? || flags.drop(1).any?
    end

    def self.normalize_keyword(keyword)
      keyword.to_s.downcase
    end
    private_class_method :normalize_keyword

    def initialize(result, snippet_text, keyword_groups, url, strict_mode: nil)
      @result = result
      @snippet_text = snippet_text.to_s
      @keyword_groups = Array(keyword_groups).map { |group| Array(group).compact.map(&:to_s) }.reject(&:empty?)
      @url = url
      @explicit_strict_mode = strict_mode
    end

    def call
      return empty_rank if @keyword_groups.empty?

      evaluation = evaluate_text(@snippet_text)
      status = evaluation[:all_matched] ? "verified" : "pending"

      build_rank(evaluation, status)
    end

    private

    def empty_rank
      RankResult.new(
        relevance_score: 0,
        matched_keywords: [],
        verification_status: "verified",
        valid?: true
      )
    end

    def evaluate_text(text)
      downcased_text = text.downcase
      group_matches = @keyword_groups.map do |group|
        group.find { |keyword| downcased_text.include?(keyword.downcase) }
      end
      group_flags = group_matches.map(&:present?)

      {
        matched_keywords: group_matches.compact,
        group_flags: group_flags,
        matched_groups_count: group_flags.count(true),
        first_group_matched: group_flags.first == true,
        subsequent_group_matched: group_flags.drop(1).any?,
        all_matched: group_flags.all?
      }
    end

    def build_rank(evaluation, status)
      RankResult.new(
        relevance_score: calculate_score(evaluation),
        matched_keywords: evaluation[:matched_keywords],
        verification_status: status,
        valid?: evaluate_validity(evaluation, status)
      )
    end

    def calculate_score(evaluation)
      total_groups = @keyword_groups.size.to_f
      score = (evaluation[:matched_groups_count].fdiv(total_groups) * MAX_SCORE).round
      score -= FIRST_GROUP_PENALTY unless evaluation[:first_group_matched]

      # In balanced mode a primary-only match is retained for page verification,
      # but must not enter the normal (> 0) inbox before a later group matches.
      if !strict_mode? && evaluation[:first_group_matched] &&
         @keyword_groups.size > 1 && !evaluation[:subsequent_group_matched]
        score = 0
      end

      score
    end

    def strict_mode?
      return @explicit_strict_mode unless @explicit_strict_mode.nil?

      @result.respond_to?(:search) && @result.search.respond_to?(:strict_mode?) && @result.search.strict_mode?
    end

    def evaluate_validity(evaluation, _status)
      return true if @keyword_groups.empty?

      # Persist partial matches so the verification job can inspect the full
      # page. The selected threshold controls which scores enter the normal
      # inbox; it must not prevent the less-relevant feed from seeing them.
      evaluation[:matched_groups_count].positive? || evaluation[:all_matched]
    end
  end
end
