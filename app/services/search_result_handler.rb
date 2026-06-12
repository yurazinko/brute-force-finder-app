# frozen_string_literal: true

class SearchResultHandler
  include Utils::UrlNormalizer

  def self.call(prompt, raw_results)
    new(prompt, raw_results).call
  end

  def initialize(prompt, raw_results)
    @prompt = prompt
    @search = prompt.search
    @raw_results = raw_results
    @now = Time.current
    @result_records = []
  end

  def call
    handle_failure if @raw_results.blank?

    collect_records
    bulk_insert_records
    check_search_completion
    true
  rescue StandardError => e
    Rails.logger.error("[Search::ResultHandler] Failed for Prompt##{@prompt.id}: #{e.message}")
    @prompt.update!(status: "failed", error_message: e.message)
    check_search_completion
    false
  end

  private

  def collect_records
    @raw_results.each do |result|
      next if (clean_url = Utils::UrlNormalizer.normalize(result["url"])).blank?

      @result_records << {
        search_id: @search.id,
        url: clean_url,
        url_hash: Utils::UrlNormalizer.hash(clean_url),
        title: result["title"],
        content: result["content"],
        created_at: @now,
        updated_at: @now
      }
    end
  end

  def bulk_insert_records
    Result.insert_all(@result_records, unique_by: %i[search_id url_hash]) if @result_records.any?

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
