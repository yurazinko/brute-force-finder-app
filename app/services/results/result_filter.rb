module Results
  class ResultFilter
    attr_reader :rank_result

    def initialize(result, prompt, target_configs)
      @result = result
      @prompt = prompt
      @target_configs = target_configs
      @url = result["url"]
      @keyword_groups = DorkParser.parse_groups(prompt&.full_query_text)
      @rank_result = nil
    end

    def valid?
      return false if @url.blank?
      return false unless UrlMatcher.matches?(@url, @prompt&.target)

      @rank_result = RelevanceRanker.call(
        @result,
        snippet_text,
        @keyword_groups,
        @url,
        time_range: @prompt&.search&.time_frame
      )

      @rank_result.valid?
    end

    private

    def snippet_text
      [@result["url"], @result["title"], @result["content"]].compact.join(" ")
    end
  end
end
