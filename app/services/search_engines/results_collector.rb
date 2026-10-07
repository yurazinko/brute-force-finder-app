# frozen_string_literal: true

module SearchEngines
  class ResultsCollector
    COLLECTORS = [
      SearchEngines::Yacy::RawResultsCollector,
      SearchEngines::Searxng::RawResultsCollector,
      SearchEngines::Fourget::RawResultsCollector,
      SearchEngines::Degoog::RawResultsCollector
    ].freeze

    def self.call(query, options = {}, &)
      new(query, options).collect(&)
    end

    def initialize(query, options = {})
      @query = query
      @options = options
    end

    def collect(&)
      seen_urls = Set.new
      failed_engines = []
      last_error = nil
      streaming = block_given?
      combined_data = streaming ? nil : []

      COLLECTORS.each do |collector_class|
        err = process_collector_step(collector_class, seen_urls, failed_engines, combined_data, &)
        last_error = err if err.present?
      end

      failed_engines.uniq!
      finalize_response(seen_urls, combined_data, failed_engines, last_error, streaming: streaming)
    end

    private

    def process_collector_step(collector_class, seen_urls, failed_engines, combined_data, &)
      result = collector_class.call(@query, @options)
      failed_engines.concat(result[:failed_engines]) if result[:failed_engines].present?

      fresh_data = filter_fresh_data(result[:data], seen_urls)
      dispatch_batch(fresh_data, collector_class.name, combined_data, &) if fresh_data.any?

      result[:error]
    end

    def filter_fresh_data(data, seen_urls)
      return [] if data.blank?

      data.reject do |item|
        url = item["url"]
        url.blank? || !seen_urls.add?(url)
      end
    end

    def dispatch_batch(fresh_data, collector_name, combined_data, &)
      if block_given?
        yield(fresh_data, collector_name)
      else
        combined_data.concat(fresh_data)
      end
    end

    def finalize_response(seen_urls, combined_data, failed_engines, last_error, streaming:)
      if streaming
        {
          success: seen_urls.any?,
          failed_engines: failed_engines,
          error: seen_urls.any? ? nil : (last_error || "No results from any engine")
        }
      else
        has_data = combined_data.any?
        {
          success: has_data,
          data: combined_data,
          failed_engines: failed_engines,
          error: has_data ? nil : (last_error || "No results from any engine")
        }
      end
    end
  end
end
