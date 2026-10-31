# frozen_string_literal: true

module Results
  class ResultFilter
    attr_reader :rank_result, :matched_pattern

    def initialize(result, prompt, search = nil)
      @result = result.with_indifferent_access
      @prompt = prompt
      @target = prompt&.target
      @search = search || (prompt.search if prompt.respond_to?(:search))
      @url = @result[:url]
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

      ranker_options = {}
      ranker_options[:strict_mode] = @search.strict_mode? if @search.respond_to?(:strict_mode?)
      @rank_result = RelevanceRanker.call(@result, snippet_text, @keyword_groups, @url, **ranker_options)
      @rank_result.valid?
    end

    private

    def snippet_text
      [@result[:url], @result[:title], @result[:content]].compact.join(" ")
    end
  end
end
