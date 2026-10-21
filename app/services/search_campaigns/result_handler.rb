# frozen_string_literal: true

module SearchCampaigns
  class ResultHandler
    def self.call(prompt, raw_results) = new(prompt, raw_results).call

    def initialize(prompt, raw_results)
      @prompt = prompt
      @search = prompt.search
      @raw_results = raw_results
      @scraped_data = raw_results.try(:[], :data) || []
    end

    def call
      return { raw_count: 0, new_count: 0 } if @scraped_data.blank?

      metrics, counts = process_and_persist_batch
      broadcast_metrics(metrics, counts)
      build_response(metrics, counts)
    rescue StandardError => e
      log_and_return_error(e)
    end

    private

    def process_and_persist_batch
      result_records = Results::DataTransformer.process(@search.id, @scraped_data, @prompt)
      metrics = Results::BatchPersister.call(@search, result_records)
      @search.results.reset
      counts = Results::Counters.calculate_filtered(@search.results, filter_options, @search)
      [metrics, counts]
    end

    def broadcast_metrics(metrics, counts)
      SearchCampaigns::LifecycleNotifier.broadcast_metrics(
        @search,
        counts,
        new_results: metrics[:persisted_results]
      )
    end

    def build_response(metrics, counts)
      {
        raw_count: metrics[:raw_count],
        new_count: metrics[:new_count],
        total: counts.total
      }
    end

    def log_and_return_error(error)
      Rails.logger.error("[Search::ResultHandler] Failed for Prompt##{@prompt.id}: #{error.message}")
      { error: error.message, raw_count: 0, new_count: 0 }
    end

    def filter_options
      {
        status: "unread",
        time_frame: @search.time_frame,
        sort: Results::Query::DEFAULT_SORT,
        show_acknowledged: @search.show_acknowledged,
        show_less_relevant: false
      }
    end
  end
end
