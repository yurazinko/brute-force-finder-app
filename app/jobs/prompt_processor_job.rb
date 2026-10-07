# frozen_string_literal: true

class PromptProcessorJob < ApplicationJob
  sidekiq_options queue: :scraping, retry: false

  def perform(prompt_id, _user_id = nil)
    updated_count = Prompt.where(id: prompt_id, status: "pending").update_all(status: "active")
    return if updated_count.zero?

    execute_pipeline(Prompt.find(prompt_id))
  rescue StandardError => e
    Prompt.where(id: prompt_id).update_all(status: "pending")
    raise e
  end

  private

  def execute_pipeline(prompt)
    search = prompt.search
    domain = extract_domain(prompt.full_query_text)
    query_text = SearchCampaigns::DorkRandomizer.perform(prompt.full_query_text)

    broadcast_live_status(search, "[#{domain}] Requesting data from Search Pipeline...")

    total_metrics = process_search_stream(prompt, search, query_text)
    broadcast_handler_result(search, domain, total_metrics)
  end

  def process_search_stream(prompt, search, query_text)
    total_metrics = { raw_count: 0, new_count: 0 }
    handler_errors = []

    collector_summary = SearchEngines::ResultsCollector.call(
      query_text,
      time_range: search.time_frame,
      dynamic_url: prompt.target&.allow_query_strings || false
    ) do |batch_raw_results, _engine_name|
      handler_result = SearchCampaigns::ResultHandler.call(prompt, { data: batch_raw_results })
      accumulate_metrics!(total_metrics, handler_errors, handler_result)
    end

    total_metrics[:error] = collector_summary[:error] || handler_errors.first
    total_metrics
  end

  def accumulate_metrics!(total_metrics, handler_errors, handler_result)
    total_metrics[:raw_count] += handler_result[:raw_count].to_i
    total_metrics[:new_count] += handler_result[:new_count].to_i
    handler_errors << handler_result[:error] if handler_result[:error].present?
  end

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
    message = if result[:new_count].to_i.positive?
                "[#{domain}] Extracted #{result[:raw_count]} links. Imported #{result[:new_count]} NEW leads!"
              else
                "[#{domain}] Extracted #{result[:raw_count]} links, but all of them are already processed."
              end

    broadcast_live_status(search, message)
  end

  def broadcast_live_status(search, message)
    broadcast_turbo_render(search, "searches/update_status", message: message)
  rescue StandardError => e
    Rails.logger.error("Turbo broadcast failed: #{e.message}")
  end

  def extract_domain(query) = query.match(/site:(\S+)/)&.captures&.first || "target"
end
