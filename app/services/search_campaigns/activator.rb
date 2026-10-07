# frozen_string_literal: true

module SearchCampaigns
  class Activator
    BATCH_SIZE = 500
    TOTAL_SCHEDULE_WINDOW = 6.hours

    def self.call(search, target_ids) = new(search, target_ids).call

    def initialize(search, target_ids)
      @search = search
      @target_ids = target_ids
      @now = Time.current
    end

    def call
      ApplicationRecord.transaction do
        @search.update!(status: "processing")

        create_prompts
        schedule_prompt_jobs
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
    end

    def unique_index_name
      if @target_ids.blank?
        :index_global_prompts_on_search_and_query
      else
        :index_prompts_on_search_target_and_query
      end
    end

    def prompts_scope
      @search.prompts.where(target_id: @target_ids.presence)
    end

    def schedule_prompt_jobs
      total_count = prompts_scope.count
      return if total_count.zero?

      broadcast_live_status("Initializing #{total_count} parallel scraping streams...")

      step = TOTAL_SCHEDULE_WINDOW / total_count
      user_id = @search.user_id
      offset = 0

      prompts_scope.in_batches(of: BATCH_SIZE) do |batch|
        offset = schedule_batch(batch, step, user_id, offset)
      end
    end

    def schedule_batch(batch, step, user_id, offset)
      batch.pluck(:id).each_with_index do |prompt_id, local_index|
        global_index = offset + local_index
        scheduled_time = calculate_scheduled_time(global_index, step)
        PromptProcessorJob.perform_at(scheduled_time, prompt_id, user_id)
      end

      offset + batch.size
    end

    def calculate_scheduled_time(index, step)
      base_time = @now + (index * step)
      jitter = rand((-step.to_f / 2)..(step.to_f / 2))

      [base_time + jitter, @now].max
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
