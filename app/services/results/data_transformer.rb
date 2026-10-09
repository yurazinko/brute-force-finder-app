# frozen_string_literal: true

module Results
  class DataTransformer
    def self.process(search_id, raw_results, prompt)
      new(search_id, raw_results, prompt).process
    end

    def initialize(search_id, raw_results, prompt)
      @search_id = search_id
      @raw_results = raw_results || []
      @prompt = prompt
      @now = Time.current
      @target_configs = fetch_target_configs
    end

    def process
      @raw_results.each_with_object([]) do |result, records|
        filter = ResultFilter.new(result, @prompt, @target_configs)
        next unless filter.valid?

        clean_url = Utils::UrlNormalizer.normalize(result["url"], target_configs: @target_configs)
        next if clean_url.blank?

        records << build_record(clean_url, result, filter.rank_result)
      end
    end

    private

    def fetch_target_configs
      Target.joins(:prompts)
            .where(prompts: { search_id: @search_id })
            .pluck(:domain, :allow_query_strings)
            .each_with_object({}) do |(domain, allow_query), configs|
              next if domain.blank?

              clean_host = Utils::UrlNormalizer.clean_domain_string(domain)
              configs[clean_host] = allow_query if clean_host.present?
            end
    end

    def build_record(clean_url, result, rank_result)
      {
        search_id: @search_id,
        url: clean_url,
        url_hash: Utils::UrlNormalizer.hash(clean_url),
        title: result["title"],
        content: result["content"],
        engine: result["engine"],
        relevance_score: rank_result.relevance_score,
        matched_keywords: rank_result.matched_keywords,
        verification_status: rank_result.verification_status,
        created_at: @now,
        updated_at: @now
      }
    end
  end
end
