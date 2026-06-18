# frozen_string_literal: true

class SearchResultHandler
  def self.call(prompt, raw_results) = new(prompt, raw_results).call

  def initialize(prompt, raw_results)
    @prompt = prompt
    @search = prompt.search
    @raw_results = raw_results
  end

  def call
    raise_failure("No results found or client error") if @raw_results.blank?

    counts = process_records
    update_content

    counts
  rescue StandardError => e
    handle_error(e)
    { error: e.message, raw_count: 0, new_count: 0 }
  ensure
    finalize_search_lifecycle
  end

  private

  def process_records
    update_lifecycle_status

    result_records = Results::DataTransformer.process(@search.id, @raw_results)
    raw_count = result_records.size

    if raw_count.positive?
      insert_and_calculate_metrics(result_records, raw_count)
    else
      @prompt.update!(status: "success")
      { raw_count: 0, new_count: 0, total: current_results_count }
    end
  end

  def insert_and_calculate_metrics(result_records, raw_count)
    exact_count_before = current_results_count

    Result.insert_all(result_records, unique_by: %i[search_id url_hash])

    exact_count_after = current_results_count
    new_count = exact_count_after - exact_count_before

    @search.results.reset
    @prompt.update!(status: "success")

    { raw_count: raw_count, new_count: new_count, total: exact_count_after }
  end

  def current_results_count = Result.where(search_id: @search.id).count

  def finalize_search_lifecycle
    check_lifecycle_status
    @search.reload
    update_lifecycle_status
    update_counters
  end

  def update_counters
    counts = @search.calculate_counters
    counter_targets(counts).each do |target_id, value|
      Turbo::StreamsChannel.broadcast_update_to(@search, :results, target: target_id, html: (value || 0).to_s)
    end
  rescue StandardError => e
    Rails.logger.error("[Search::ResultHandler] Counters broadcast failed: #{e.message}")
  end

  def counter_targets(counts)
    {
      "counter_all_clean" => counts[:all_clean],
      "counter_unread" => counts[:unread],
      "counter_interesting" => counts[:interesting],
      "counter_watched" => counts[:watched],
      "counter_garbage" => counts[:garbage],
      "results_count" => "Showing: #{@search.results.count}"
    }
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

  def check_lifecycle_status
    return if @search.prompts.exists?(status: %w[pending active])

    @search.update!(status: "completed")
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
