# frozen_string_literal: true

module Results
  class DataTransformer
    WWW_PREFIX = "www."

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
        next unless ResultFilter.new(result, @prompt, @target_configs).valid?

        domain = extract_domain(result["url"])
        next if domain.blank?

        clean_url = normalize_url(result["url"], domain)
        next if clean_url.blank?

        records << build_record(clean_url, result)
      end
    end

    private

    def fetch_target_configs
      Target.joins(:prompts)
            .where(prompts: { search_id: @search_id })
            .pluck(:domain, :allow_query_strings)
            .to_h
    end

    def extract_domain(url)
      host = URI.parse(url).host
      host&.start_with?(WWW_PREFIX) ? host.sub(WWW_PREFIX, "") : host
    rescue URI::InvalidURIError
      nil
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
