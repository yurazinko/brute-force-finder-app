# frozen_string_literal: true

module SearchCampaigns
  class Activator
    def self.call(search, target_ids) = new(search, target_ids).call

    def initialize(search, target_ids)
      @search = search
      @target_ids = target_ids
      @now = Time.current
    end

    def call
      return false if @target_ids.blank? || targets_data.blank?

      ApplicationRecord.transaction do
        @search.update!(status: "processing")

        inserted_ids = create_prompts
        perform_workers(inserted_ids)
      end

      true
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::Activator] Critical failure for Search##{@search.id}: #{e.message}")
      false
    end

    private

    def create_prompts
      Prompt.upsert_all(
        query_records,
        unique_by: :index_prompts_on_search_target_and_query,
        update_only: %i[status]
      )

      @search.prompts.where(target_id: @target_ids).pluck(:id)
    end

    def perform_workers(prompt_ids)
      return if prompt_ids.blank?

      broadcast_live_status("Initializing #{prompt_ids.size} parallel scraping streams...")

      prompt_ids.shuffle.each_with_index do |prompt_id, index| # TODO: investigate if job can fail due to timeout
        delay = index + rand(10..30)

        PromptProcessorJob.perform_in(delay.minutes, prompt_id)
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
      Rails.logger.error("[SearchCampaigns::Activator] Live status broadcast failed: #{e.message}")
    end
  end
end
