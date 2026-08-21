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
      @target = prompt&.target
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
      return unless url_matches_target?(url)

      domain = extract_domain(url)
      return if domain.blank?

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

    def url_matches_target?(url)
      return true if @target.blank? || @target.domain.blank?

      target_host, target_path = parse_target_domain
      uri = URI.parse(url)
      result_host = uri.host&.sub(WWW_PREFIX, "")

      return false unless host_matches?(result_host, target_host)

      path_matches?(uri.path, target_path)
    rescue URI::InvalidURIError
      false
    end

    def parse_target_domain
      target_str = @target.domain.to_s.sub(%r{\Ahttps?://}, "").sub(WWW_PREFIX, "")
      target_str.split("/", 2)
    end

    def host_matches?(result_host, target_host)
      return false if result_host.blank?

      result_host == target_host || result_host.end_with?(".#{target_host}")
    end

    def path_matches?(result_path, target_path)
      return true if target_path.blank?

      result_path.to_s.delete_prefix("/").start_with?(target_path)
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
