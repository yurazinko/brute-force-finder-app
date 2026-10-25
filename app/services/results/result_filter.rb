# frozen_string_literal: true

module Results
  class ResultFilter
    attr_reader :rank_result, :matched_pattern

    def initialize(result, prompt, target_configs)
      @result = result
      @prompt = prompt
      @target = prompt&.target
      @target_configs = target_configs
      @url = result["url"]
      @keyword_groups = DorkParser.parse_groups(prompt&.full_query_text)
      @rank_result = nil
      @matched_pattern = nil
    end

    def valid?
      return false if @url.blank?

      if @target.present? && @target.domain.present?
        matcher = UrlMatcher.new(@url, @target)

        return false unless matcher.domain_matches?

        @matched_pattern = matcher.matched_pattern

        return false if matcher.active_patterns? && @matched_pattern.nil?
      end

      @rank_result = RelevanceRanker.call(@result, snippet_text, @keyword_groups, @url)
      @rank_result.valid?
    end

    private

    def snippet_text
      [@result["url"], @result["title"], @result["content"]].compact.join(" ")
    end
  end
end
