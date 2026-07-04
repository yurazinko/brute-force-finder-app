# frozen_string_literal: true

module Results
  class DataTransformer
    def self.process(search_id, raw_results, target)
      new(search_id, raw_results, target).process
    end

    def initialize(search_id, raw_results, target)
      @search_id = search_id
      @raw_results = raw_results || []
      @target = target
      @now = Time.current

      @target_configs = Target.joins(:prompts)
                              .where(prompts: { search_id: search_id })
                              .pluck(:domain, :allow_query_strings)
                              .to_h
    end

    def process
      @raw_results.each_with_object([]) do |result, records|
        next if result["url"].blank?

        domain = extract_domain(result["url"])
        next if domain.blank?

        next unless domain_matches_target?(domain)

        keep_query = @target_configs[domain] || false

        clean_url = Utils::UrlNormalizer.normalize(result["url"], keep_query: keep_query)
        next if clean_url.blank?

        records << {
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

    private

    def extract_domain(url)
      URI.parse(url).host&.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end

    def domain_matches_target?(result_domain)
      target_domain = @target.domain.delete_prefix("www.")

      result_domain == target_domain || result_domain.end_with?(".#{target_domain}")
    end
  end
end
