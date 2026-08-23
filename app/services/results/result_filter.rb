# frozen_string_literal: true

module Results
  class ResultFilter
    def initialize(result, prompt, target_configs)
      @result = result
      @prompt = prompt
      @target_configs = target_configs
      @url = result["url"]
      @keyword_groups = DorkParser.parse_groups(prompt&.full_query_text)
    end

    def valid?
      return false if @url.blank?
      return false unless UrlMatcher.matches?(@url, @prompt&.target)

      return true if matches_keywords?(snippet_text)

      fetch_and_verify_page
    end

    private

    def snippet_text
      [@result["url"], @result["title"], @result["content"]].compact.join(" ")
    end

    def fetch_and_verify_page
      res = PageFetcher.fetch(@url)
      return true if res.captcha_detected? || res.error?

      matches_keywords?(res.text)
    end

    def matches_keywords?(text)
      return true if @keyword_groups.empty?

      downcased_text = text.downcase
      @keyword_groups.all? do |group|
        group.any? { |kw| downcased_text.include?(kw.downcase) }
      end
    end
  end
end
