# frozen_string_literal: true

module Results
  class DataTransformer
    def self.process(search_id, raw_results)
      new(search_id, raw_results).process
    end

    def initialize(search_id, raw_results)
      @search_id = search_id
      @raw_results = raw_results || []
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
  end
end
