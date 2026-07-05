# frozen_string_literal: true

module Results
  class DataTransformer
    WWW_PREFIX = "www."

    def self.process(search_id, raw_results, target)
      new(search_id, raw_results, target).process
    end

    def initialize(search_id, raw_results, target)
      @search_id = search_id
      @raw_results = raw_results || []
      @target = target
      @now = Time.current
      @target_configs = fetch_target_configs
    end

    def process
      @raw_results.each_with_object([]) do |result, records|
        attributes = transform_result(result)
        records << attributes if attributes
      end
    end

    private

    def fetch_target_configs
      Target.joins(:prompts)
            .where(prompts: { search_id: @search_id })
            .pluck(:domain, :allow_query_strings)
            .to_h
    end

    def transform_result(result)
      url = result["url"]
      return if url.blank?

      domain = extract_domain(url)
      return if domain.blank? || !domain_matches_target?(domain)

      clean_url = normalize_url(url, domain)
      return if clean_url.blank?

      build_record(clean_url, result)
    end

    def extract_domain(url)
      host = URI.parse(url).host
      host&.start_with?(WWW_PREFIX) ? host.sub(WWW_PREFIX, "") : host
    rescue URI::InvalidURIError
      nil
    end

    def domain_matches_target?(result_domain)
      return true if @target.blank?

      target_domain = @target.domain.to_s.start_with?(WWW_PREFIX) ? @target.domain.sub(WWW_PREFIX, "") : @target.domain

      result_domain == target_domain || result_domain.end_with?(".#{target_domain}")
    end

    def normalize_url(url, domain)
      keep_query = @target_configs[domain] || false
      Utils::UrlNormalizer.normalize(url, keep_query: keep_query)
    end

    def build_record(clean_url, result)
      {
        search_id: @search_id,
        url: clean_url,
        url_hash: Utils::UrlNormalizer.hash(clean_url),
        title: result["title"],
        content: result["content"],
        created_at: @now,
        updated_at: @now
      }
    end
  end
end
