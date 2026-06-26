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
    metrics = Results::BatchPersister.call(@search.id, result_records)

    @search.results.reset
    @prompt.update!(status: "success")

    begin
      db_counts = fetch_aggregated_counters
      @total_cached = db_counts.values.sum

      broadcast_counters(db_counts)
      update_content
    rescue StandardError => e
      Rails.logger.error("[Search::ResultHandler] Frontend broadcast failed: #{e.message}")
      @total_cached ||= Result.where(search_id: @search.id).count
    end

    {
      raw_count: metrics[:raw_count],
      new_count: metrics[:new_count],
      total: @total_cached
    }
  end

  def fetch_aggregated_counters
    Result.where(search_id: @search.id)
          .group(:status)
          .count
  end

  def finalize_search_lifecycle
    return if @prompt.reload.status == "failed"

    check_lifecycle_status
    @search.reload
    update_lifecycle_status
  end

  def broadcast_counters(db_counts)
    mapped_counts = {
      all_clean: db_counts.except("garbage").values.sum,
      unread: db_counts["unread"] || 0,
      interesting: db_counts["interesting"] || 0,
      watched: db_counts["watched"] || 0,
      garbage: db_counts["garbage"] || 0
    }

    counter_targets(mapped_counts, @total_cached).each do |target_id, value|
      Turbo::StreamsChannel.broadcast_update_to(@search, :results, target: target_id, html: (value || 0).to_s)
    end
  end

  def counter_targets(counts, total_count)
    {
      "counter_all_clean" => counts[:all_clean],
      "counter_unread" => counts[:unread],
      "counter_interesting" => counts[:interesting],
      "counter_watched" => counts[:watched],
      "counter_garbage" => counts[:garbage],
      "results_count" => "Showing: #{total_count}"
    }
  end

  def update_content
    return if @prompt.reload.status == "failed"

    latest_results = Result.where(search_id: @search.id).without_garbage.order(created_at: :desc).limit(20)

    Turbo::StreamsChannel.broadcast_replace_to(
      @search, :results,
      target: "results_pool_list",
      partial: "searches/results_pool_content",
      locals: { results: latest_results }
    )
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
