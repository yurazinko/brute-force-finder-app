# frozen_string_literal: true

module SearchEngines
  class BaseRawResultsCollector
    def self.call(query, options = {}) = new(query, options).collect

    def initialize(query, options = {})
      @query = query
      @options = options
      @failed_engines = []
      @errors = []
    end

    def collect
      seen_urls = Set.new
      collected_data = []

      client_classes.each do |client_class|
        process_client(client_class, collected_data, seen_urls)
      end

      {
        success: collected_data.any?,
        data: collected_data,
        failed_engines: @failed_engines.uniq,
        error: collected_data.empty? ? @errors.join(", ").presence : nil
      }
    end

    private

    def client_classes
      raise NotImplementedError, "#{self.class} must define #client_classes"
    end

    def process_client(client_class, collected_data, seen_urls)
      result = client_class.search(@query, @options)

      extract_fresh_items(result[:data], seen_urls) { |item| collected_data << item }

      @failed_engines.concat(result[:failed_engines]) if result[:failed_engines].is_a?(Array)

      record_client_failure(client_class.name, result[:error]) unless result[:success]
    end

    def extract_fresh_items(raw_items, seen_urls)
      return unless raw_items.is_a?(Array)

      raw_items.each do |item|
        url = item["url"]
        yield(item) if url.present? && seen_urls.add?(url)
      end
    end

    def record_client_failure(client_name, error)
      return if error.blank?

      @errors << "#{client_name}: #{error}"
    end
  end
end
