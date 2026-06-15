# frozen_string_literal: true

class PromptProcessorJob
  include Sidekiq::Job

  sidekiq_options queue: :scraping, retry: 3

  def perform(prompt_id)
    prompt = Prompt.find_by(id: prompt_id)
    return unless prompt
    return unless prompt.status == "pending"

    prompt.update!(status: "active")

    raw_results = Searxng::TorClient.search(
      prompt.full_query_text,
      time_range: prompt.search.time_frame
    )

    SearchResultHandler.call(prompt, raw_results)
  end
end
