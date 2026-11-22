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

        result = build_single_result(raw_result)
        next unless result

        built << result
        @count += 1
      end
    end

    private

    attr_reader :prompt, :search, :seen_hashes

    def build_single_result(raw_result)
      item = raw_result.with_indifferent_access
      normalized_url = Utils::UrlNormalizer.normalize(item[:url])
      return if normalized_url.blank?

      item[:url] = normalized_url
      filter = Results::ResultFilter.new(item, prompt, search)
      return unless filter.valid?

      url_hash = Utils::UrlNormalizer.hash(normalized_url)
      return unless url_hash.present? && seen_hashes.add?(url_hash)

      instantiate_result(item, normalized_url, url_hash, filter.rank_result)
    rescue URI::InvalidURIError, TypeError => e
      Rails.logger.debug { "[QuickSearch::ResultBuilder] Skipping malformed result: #{e.message}" }
      nil
    end

    def instantiate_result(item, normalized_url, url_hash, rank)
      now = Time.current

      Result.new(
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
        created_at: now,
        updated_at: now
      ).tap { |record| record.search = search }
    end
  end
end
