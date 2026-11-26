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

      metrics, total = process_and_persist_batch
      broadcast_new_results(metrics)
      build_response(metrics, total)
    rescue StandardError => e
      report_and_reraise(e)
    end

    private

    def process_and_persist_batch
      result_records = Results::DataTransformer.process(@search, @scraped_data, @prompt)
      metrics = Results::BatchPersister.call(@search, @prompt, result_records)
      @search.results.reset
      total = Results::Query.new(@search.results, filter_options, search: @search).filtered_scope.count
      SearchCampaigns::CountersRefreshScheduler.schedule(@search)
      [metrics, total]
    end

    def broadcast_new_results(metrics)
      SearchCampaigns::LifecycleNotifier.broadcast_new_results(
        @search, metrics[:persisted_results]
      )
    end

    def build_response(metrics, total)
      { raw_count: metrics[:raw_count], new_count: metrics[:new_count], total: total }
    end

    def report_and_reraise(error)
      begin
        Rails.error.report(
          error, handled: false, severity: :error,
                 context: { prompt_id: @prompt.id, search_id: @search.id }
        )
      rescue StandardError => e
        Rails.logger.error("[Search::ResultHandler] Error reporter failed: #{e.message}")
      end

      Rails.logger.error("[Search::ResultHandler] Failed for Prompt##{@prompt.id}: #{error.message}")
      raise error
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
