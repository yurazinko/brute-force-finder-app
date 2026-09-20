# frozen_string_literal: true

module Results
  class ResultFilter
    # TODO: Implement better memory consuming approach for large pages, e.g., streaming and searching in chunks
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

      @rank_result = RelevanceRanker.call(@result, snippet_text, @keyword_groups, @url)
      @rank_result.valid?
    end

    private

    def snippet_text
      [@result["url"], @result["title"], @result["content"]].compact.join(" ")
    end
  end
end
