# frozen_string_literal: true

module QuickSearch
  class ResultBuilder
    MAX_RESULTS = 100

    attr_reader :count

    def initialize(prompt:)
      @prompt = prompt
      @search = prompt.search
      @seen_hashes = Set.new
      @count = 0
    end

    def build(raw_results)
      Array(raw_results).each_with_object([]) do |raw_result, built|
        break built if @count >= MAX_RESULTS

        item = raw_result.with_indifferent_access
        normalized_url = Utils::UrlNormalizer.normalize(item[:url])
        next if normalized_url.blank?

        item[:url] = normalized_url
        filter = Results::ResultFilter.new(item, @prompt, @search)
        next unless filter.valid?

        url_hash = Utils::UrlNormalizer.hash(normalized_url)
        next unless url_hash.present? && @seen_hashes.add?(url_hash)

        rank = filter.rank_result
        result = Result.new(
          url: normalized_url,
          url_hash: url_hash,
          title: item[:title],
          content: item[:content],
          engine: item[:engine],
          status: "unread",
          acknowledged: false,
          relevance_score: rank.relevance_score,
          matched_keywords: rank.matched_keywords,
          verification_status: rank.verification_status,
          created_at: Time.current,
          updated_at: Time.current
        )
        result.search = @search

        built << result
        @count += 1
      rescue URI::InvalidURIError, TypeError => e
        Rails.logger.debug { "[QuickSearch::ResultBuilder] Skipping malformed result: #{e.message}" }
      end
    end
  end
end
