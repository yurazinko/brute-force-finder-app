# frozen_string_literal: true

module SearchCampaigns
  class ResultHandler
    def self.call(prompt, raw_results) = new(prompt, raw_results).call

    def initialize(prompt, raw_results)
      @prompt = prompt
      @search = prompt.search
      @raw_results = raw_results
      @scraped_data = raw_results.try(:[], :data) || []
      @coordinator = SearchCampaigns::PipelineCoordinator.new(prompt)
    end

    def call
      if @scraped_data.blank?
        @coordinator.fail!("No results found or client error")
        return { error: "No results found or client error", raw_count: 0, new_count: 0 }
      end

      metrics = process_records
      metrics
    rescue StandardError => e
      Rails.logger.error("[Search::ResultHandler] Failed for Prompt##{@prompt.id}: #{e.message}")
      @coordinator.fail!(e.message)
      { error: e.message, raw_count: 0, new_count: 0 }
    ensure
      @coordinator.evaluate_completion!
      SearchCampaigns::LifecycleNotifier.broadcast_status(@search)
    end

    private

    def process_records
      result_records = Results::DataTransformer.process(@search.id, @scraped_data)
      metrics = Results::BatchPersister.call(@search.id, result_records)

      @search.results.reset
      @coordinator.success!

      db_counts = Result.where(search_id: @search.id).group(:status).count
      total_cached = db_counts.values.sum

      SearchCampaigns::LifecycleNotifier.broadcast_metrics(@search, db_counts, total_cached)

      {
        raw_count: metrics[:raw_count],
        new_count: metrics[:new_count],
        total: total_cached
      }
    end
  end
end
