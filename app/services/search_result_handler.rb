# frozen_string_literal: true

class SearchResultHandler
  def self.call(prompt, raw_results)
    new(prompt, raw_results).call
  end

  def initialize(prompt, raw_results)
    @prompt = prompt
    @search = prompt.search
    @raw_results = raw_results
    @now = Time.current
  end

  def call
    handle_failure if @raw_results.blank?

    bulk_insert_result_records
    check_search_completion
    true
  rescue StandardError => e
    Rails.logger.error("[Search::ResultHandler] Failed for Prompt##{@prompt.id}: #{e.message}")
    @prompt.update!(status: "failed", error_message: e.message)
    check_search_completion
    false
  end

  private

  def bulk_insert_result_records
    result_records = @raw_results.map do |result|
      {
        search_id: @search.id,
        url: result["url"],
        title: result["title"],
        content: result["content"],
        created_at: @now,
        updated_at: @now
      }
    end

    Result.insert_all(result_records) if result_records.any?

    @prompt.update!(status: "success")
  end

  def handle_failure
    @prompt.update!(status: "failed", error_message: "No results found or client error")
    check_search_completion
    raise("No results found or client error")
  end

  def check_search_completion
    return if @search.prompts.exists?(status: %w[pending active])

    @search.update!(status: "completed")
  end
end
