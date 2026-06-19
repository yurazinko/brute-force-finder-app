# frozen_string_literal: true

class SearchActivator
  def self.call(search, target_ids) = new(search, target_ids).call

  def initialize(search, target_ids)
    @search = search
    @target_ids = target_ids
    @now = Time.current
  end

  def call
    return false if @target_ids.blank? || targets_data.blank?

    inserted_ids = create_prompts
    perform_workers(inserted_ids)

    @search.update!(status: "processing")
    true
  rescue StandardError => e
    Rails.logger.error("[SearchActivator] Critical failure for Search##{@search.id}: #{e.message}")
    false
  end

  private

  def create_prompts
    Prompt.upsert_all(
      query_records,
      unique_by: %i[target_id full_query_text],
      update_only: %i[search_id status],
      returning: %i[id]
    ).pluck("id")
  end

  def perform_workers(prompt_ids)
    return if prompt_ids.blank?

    broadcast_live_status("Initializing #{prompt_ids.size} parallel scraping streams...")

    prompt_ids.shuffle.each_with_index do |prompt_id, index|
      delay = (index * 5) + rand(5..25)
      sleep(delay) if Rails.env.development?

      PromptProcessorJob.perform_in(delay.seconds, prompt_id, prompt_ids.size, index + 1)
    end
  end

  def targets_data = @targets_data ||= Target.active.where(id: @target_ids).pluck(:id, :domain)

  def query_records
    @query_records ||= targets_data.map do |target_id, domain|
      {
        search_id: @search.id,
        target_id: target_id,
        full_query_text: "site:#{domain} #{@search.query_conditions}",
        status: "pending",
        created_at: @now,
        updated_at: @now
      }
    end
  end

  def broadcast_live_status(message)
    Turbo::StreamsChannel.broadcast_render_to(
      @search, :results,
      template: "searches/update_status",
      assigns: { message: message }
    )
  rescue StandardError => e
    Rails.logger.error("[SearchActivator] Live status broadcast failed: #{e.message}")
  end
end
