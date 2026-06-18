# frozen_string_literal: true

class PromptProcessorJob
  include Sidekiq::Job

  sidekiq_options queue: :scraping, retry: 3

  def perform(prompt_id)
    prompt = Prompt.find_by(id: prompt_id)
    return unless prompt&.status == "pending"

    search = prompt.search
    prompt.update!(status: "active")
    domain = extract_domain(prompt.full_query_text)

    broadcast_live_status(search, "[#{domain}] Requesting data from SearXNG via Tor...")
    raw_results = Searxng::TorClient.search(prompt.full_query_text, time_range: search.time_frame)

    handler_result = SearchResultHandler.call(prompt, raw_results)
    process_handler_result(search, domain, handler_result)

    check_pipeline_completion(search)
  end

  private

  def process_handler_result(search, domain, result)
    if result[:error]
      broadcast_live_status(search, "Engine error on #{domain}: #{result[:error]}")
    elsif result[:raw_count].positive?
      broadcast_success_status(search, domain, result)
    else
      broadcast_live_status(search, "[#{domain}] 0 valid URLs extracted (no matches or engine temporary blocked).")
    end
  end

  def broadcast_success_status(search, domain, result)
    if result[:new_count].positive?
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

  def check_pipeline_completion(search)
    return if search.prompts.exists?(status: %w[pending active])

    broadcast_live_status(search, "Pipeline finished. All parallel streams successfully synced.")
  end

  def broadcast_live_status(search, message)
    Thread.new do # rubocop:disable ThreadSafety/NewThread
      Turbo::StreamsChannel.broadcast_render_to(
        search, :results,
        template: "searches/update_status",
        assigns: { message: message }
      )
    end
  rescue StandardError => e
    Rails.logger.error("[PromptProcessorJob] Live status broadcast failed: #{e.message}")
  end

  def extract_domain(query) = query.match(/site:(\S+)/)&.captures&.first || "target"
end
