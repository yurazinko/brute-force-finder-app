# frozen_string_literal: true

class SearchResultHandler
  def self.call(prompt, raw_results)
    new(prompt, raw_results).call
  end

  def initialize(prompt, raw_results)
    @prompt = prompt
    @search = prompt.search
    @raw_results = raw_results
  end

  def call
    raise_failure("No results found or client error") if @raw_results.blank?

    process_records
    update_content
    true
  rescue StandardError => e
    handle_error(e)
    false
  ensure
    Searches::LifecycleManager.check_completion(@search)
    @search.reload
    update_lifecycle_status
    update_counters
  end

  private

  def process_records
    update_lifecycle_status
    result_records = Results::DataTransformer.process(@search.id, @raw_results)

    Result.insert_all(result_records, unique_by: %i[search_id url_hash]) if result_records.any?
    @prompt.update!(status: "success")
  end

  def update_counters
    counts = @search.calculate_counters

    {
      "counter_all_clean" => counts[:all_clean],
      "counter_interesting" => counts[:interesting],
      "counter_watched" => counts[:watched],
      "counter_garbage" => counts[:garbage],
      "results_count" => "Showing: #{@search.results.count}"
    }.each do |target_id, value|
      Turbo::StreamsChannel.broadcast_update_to(@search, :results, target: target_id, html: (value || 0).to_s)
    end
  rescue StandardError => e
    Rails.logger.error("[Search::ResultHandler] Counters broadcast failed: #{e.message}")
  end

  def update_content
    latest_results = @search.results.without_garbage.order(created_at: :desc).limit(20)

    Turbo::StreamsChannel.broadcast_replace_to(
      @search, :results,
      target: "results_pool_list",
      partial: "searches/results_pool_content",
      locals: { results: latest_results }
    )
  rescue StandardError => e
    Rails.logger.error("[Search::ResultHandler] ActionCable broadcast failed: #{e.message}")
  end

  def update_lifecycle_status
    Turbo::StreamsChannel.broadcast_update_to(
      @search, :results,
      target: "search_lifecycle_status",
      html: ApplicationController.render(
        partial: "searches/status_content",
        locals: { search: @search }
      )
    )
  rescue StandardError => e
    Rails.logger.error("[Search::ResultHandler] Lifecycle broadcast failed: #{e.message}")
  end

  def raise_failure(message)
    @prompt.update!(status: "failed", error_message: message)
    raise(message)
  end

  def handle_error(error)
    Rails.logger.error("[Search::ResultHandler] Failed for Prompt##{@prompt.id}: #{error.message}")
    @prompt.update!(status: "failed", error_message: error.message)
  end
end
