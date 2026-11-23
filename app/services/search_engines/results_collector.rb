# frozen_string_literal: true

module SearchEngines
  class ResultsCollector
    COLLECTORS = [
      SearchEngines::Degoog::RawResultsCollector,
      SearchEngines::Yacy::RawResultsCollector,
      SearchEngines::Searxng::RawResultsCollector,
      SearchEngines::Fourget::RawResultsCollector
    ].freeze

    def self.call(query, options = {}, on_engine_start: nil, **keyword_options, &)
      merged_options = options.to_h.merge(keyword_options)
      new(query, merged_options, on_engine_start: on_engine_start).collect(&)
    end

    def initialize(query, options = {}, on_engine_start: nil)
      @query = query
      @options = options || {}
      @on_engine_start = on_engine_start
    end

    def collect(&)
      seen_urls = Set.new
      failed_engines = []
      last_error = nil
      streaming = block_given?
      combined_data = streaming ? nil : []

      enabled_collectors.each do |collector_class|
        err = process_collector_step(collector_class, seen_urls, failed_engines, combined_data, &)
        last_error = err if err.present?
      end

      failed_engines.uniq!
      finalize_response(seen_urls, combined_data, failed_engines, last_error, streaming: streaming)
    end

    private

    def enabled_collectors
      disabled = Array(@options[:disabled_engines]).map { |engine| normalize_engine_name(engine) }
      COLLECTORS.reject { |collector| disabled.include?(normalize_engine_name(collector)) }
    end

    def normalize_engine_name(engine)
      name = engine.is_a?(Class) ? engine.name : engine.to_s
      parts = name.split("::")
      name = parts[-2] if parts.last.to_s.end_with?("RawResultsCollector") && parts.size > 1
      name.to_s.delete_suffix("RawResultsCollector").downcase
    end

    def collector_options
      @options.except(:disabled_engines)
    end

    def process_collector_step(collector_class, seen_urls, failed_engines, combined_data, &)
      notify_engine_start(collector_class)
      result = collector_class.call(@query, collector_options)
      failed_engines.concat(result[:failed_engines]) if result[:failed_engines].present?

      fresh_data = filter_fresh_data(result[:data], seen_urls)
      dispatch_batch(fresh_data, collector_class.name, combined_data, &) if fresh_data.any?

      result[:error]
    end

    def notify_engine_start(collector_class)
      @on_engine_start&.call(collector_class)
    rescue StandardError => e
      Rails.logger.warn("[ResultsCollector] Engine progress callback failed: #{e.message}")
    end

    def filter_fresh_data(data, seen_urls)
      return [] if data.blank?

      data.reject do |item|
        url = item[:url]
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
