# frozen_string_literal: true

module SearchEngines
  class ResultsCollector
    COLLECTORS = [
      SearchEngines::Yacy::RawResultsCollector,
      SearchEngines::Searxng::RawResultsCollector
    ].freeze

    def self.call(query, options = {}) = new(query, options).collect

    def initialize(query, options = {})
      @query = query
      @options = options
    end

    def collect
      combined_data = []
      failed_engines = []
      last_error = nil

      COLLECTORS.each do |collector_class|
        last_error = process_collector(collector_class, combined_data, failed_engines) || last_error
      end

      combined_data.uniq! { |r| r["url"] }

      build_response(combined_data, failed_engines, last_error)
    end

    private

    def process_collector(collector_class, combined_data, failed_engines)
      result = collector_class.call(@query, @options)

      combined_data.concat(result[:data]) if result[:success] && result[:data].present?
      failed_engines.concat(result[:failed_engines]) if result[:failed_engines].present?

      result[:error]
    end

    def build_response(combined_data, failed_engines, last_error)
      has_data = combined_data.any?

      {
        success: has_data,
        data: combined_data,
        failed_engines: failed_engines.uniq,
        error: has_data ? nil : (last_error || "No results from any engine")
      }
    end
  end
end
