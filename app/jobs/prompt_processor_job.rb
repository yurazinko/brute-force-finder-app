# frozen_string_literal: true

class PromptProcessorJob
  include Sidekiq::Job

  sidekiq_options queue: :scraping, retry: false

  def perform(prompt_id)
    updated_count = Prompt.where(id: prompt_id, status: "pending").update_all(status: "active")
    return if updated_count.zero?

    prompt = Prompt.find(prompt_id)
    search = prompt.search
    domain = extract_domain(prompt.full_query_text)
    query_text = SearchCampaigns::DorkRandomizer.perform(prompt.full_query_text)

    broadcast_live_status(search, "[#{domain}] Requesting data from Multi-Instance SearXNG Collector...")
    raw_results = Searxng::RawResultsCollector.call(query_text, time_range: search.time_frame)

    handler_result = SearchCampaigns::ResultHandler.call(prompt, raw_results)
    broadcast_handler_result(search, domain, handler_result)
  rescue StandardError => e
    Prompt.where(id: prompt_id).update_all(status: "pending")
    raise e
  end

  private

  def broadcast_handler_result(search, domain, result)
    if result[:error].present?
      broadcast_live_status(search, "[#{domain}] Engine error: #{result[:error]}")
    elsif result[:raw_count].to_i.positive?
      broadcast_success_status(search, domain, result)
    else
      broadcast_live_status(search, "[#{domain}] 0 valid URLs extracted (no matches or engines temporary blocked).")
    end
  end

  def broadcast_success_status(search, domain, result)
    if result[:new_count].to_i.positive?
      broadcast_live_status(
        search,
        "[#{domain}] Extracted #{result[:raw_count]} links. Imported #{result[:new_count]} NEW leads!"
      )
    else
      broadcast_live_status(
        search,
        "[#{domain}] Extracted #{result[:raw_count]} links, but all of them are already processed."
      )
    end
  end

  def broadcast_live_status(search, message)
    Turbo::StreamsChannel.broadcast_render_to(
      search, :results,
      template: "searches/update_status",
      assigns: { message: message }
    )
  rescue StandardError => e
    Rails.logger.error("[PromptProcessorJob] Live status broadcast failed: #{e.message}")
  end

  def extract_domain(query) = query.match(/site:(\S+)/)&.captures&.first || "target"
end
