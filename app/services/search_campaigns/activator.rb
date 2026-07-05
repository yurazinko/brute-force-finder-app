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
        prompt_records,
        unique_by: unique_index_name,
        update_only: %i[status]
      )
      fetch_inserted_prompt_ids
    end

    def unique_index_name
      if @target_ids.blank?
        :index_global_prompts_on_search_and_query
      else
        :index_prompts_on_search_target_and_query
      end
    end

    def fetch_inserted_prompt_ids
      @search.prompts.where(target_id: @target_ids.presence).pluck(:id)
    end

    def perform_workers(prompt_ids)
      return if prompt_ids.blank?

      broadcast_live_status("Initializing #{prompt_ids.size} parallel scraping streams...")

      prompt_ids.shuffle.each_with_index do |prompt_id, index|
        PromptProcessorJob.perform_in(calculate_delay(index), prompt_id)
      end
    end

    def calculate_delay(index)
      ((index * 2) + rand(30..45)).minutes
    end

    def targets_data = @targets_data ||= Target.active.where(id: @target_ids).pluck(:id, :domain)

    def prompt_records
      @prompt_records ||= @target_ids.blank? ? global_prompt_record : target_prompt_records
    end

    def global_prompt_record
      [
        base_prompt_attributes(nil, @search.query_conditions)
      ]
    end

    def target_prompt_records
      targets_data.map do |target_id, domain|
        base_prompt_attributes(target_id, "site:#{domain} #{@search.query_conditions}")
      end
    end

    def base_prompt_attributes(target_id, query_text)
      {
        search_id: @search.id,
        target_id: target_id,
        full_query_text: query_text,
        status: "pending",
        created_at: @now,
        updated_at: @now
      }
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
