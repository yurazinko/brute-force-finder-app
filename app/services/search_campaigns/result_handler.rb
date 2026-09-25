# frozen_string_literal: true

module SearchCampaigns
  class ResultHandler
    def self.call(prompt, raw_results) = new(prompt, raw_results).call

    def initialize(prompt, raw_results)
      @prompt = prompt
      @search = prompt.search
      @target = prompt.target
      @raw_results = raw_results
      @scraped_data = raw_results.try(:[], :data) || []
      @coordinator = SearchCampaigns::PipelineCoordinator.new(prompt)
    end

    def call
      if @scraped_data.blank?
        @coordinator.fail!("No results found")
        return { error: "No results found", raw_count: 0, new_count: 0 }
      end

      process_records
    rescue StandardError => e
      Rails.logger.error("[Search::ResultHandler] Failed for Prompt##{@prompt.id}: #{e.message}")
      @coordinator.fail!(e.message)
      { error: e.message, raw_count: 0, new_count: 0 }
    ensure
      safely_evaluate_completion
    end

    private

    def process_records
      result_records = Results::DataTransformer.process(@search.id, @scraped_data, @prompt)
      metrics = Results::BatchPersister.call(@search.id, result_records)

      @search.results.reset
      @coordinator.success!

      counts = Results::Counters.calculate_filtered(@search.results, filter_options, @search)
      SearchCampaigns::LifecycleNotifier.broadcast_metrics(@search, counts)

      {
        raw_count: metrics[:raw_count],
        new_count: metrics[:new_count],
        total: counts.total
      }
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

    def safely_evaluate_completion
      @coordinator.evaluate_completion!
      SearchCampaigns::LifecycleNotifier.broadcast_status(@search)
    rescue StandardError => e
      Rails.logger.error("[Search::ResultHandler] Ensure broadcast failed: #{e.message}")
    end
  end
end
