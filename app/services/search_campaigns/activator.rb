# frozen_string_literal: true

module SearchCampaigns
  class Activator
    BATCH_SIZE = 500
    TOTAL_SCHEDULE_WINDOW = 6.hours

    def self.call(search, target_ids, schedule_now) = new(search, target_ids, schedule_now).call

    def initialize(search, target_ids, schedule_now)
      @search = search
      @target_ids = target_ids
      @schedule_now = schedule_now
      @now = Time.current
    end

    def call
      prompts_to_schedule = []

      ApplicationRecord.transaction do
        cleanup_obsolete_prompts
        create_prompts

        if @schedule_now
          @search.update!(status: "processing")
          prompts_to_schedule = collect_prompts_to_schedule
        end
      end

      schedule_prompt_jobs(prompts_to_schedule) if prompts_to_schedule.any?
      true
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::Activator] Critical failure for Search##{@search.id}: #{e.message}")
      false
    end

    private

    def create_prompts = Prompt.upsert_all(prompt_records, unique_by: unique_index_name, update_only: %i[status])

    def unique_index_name
      @target_ids.blank? ? :index_global_prompts_on_search_and_query : :index_prompts_on_search_target_and_query
    end

    def prompts_scope = @search.prompts.where(target_id: @target_ids.presence)

    def collect_prompts_to_schedule
      scope = prompts_scope
      total_count = scope.count
      return [] if total_count.zero?

      broadcast_live_status("Initializing #{total_count} parallel scraping streams...")
      build_scheduled_payloads(scope, TOTAL_SCHEDULE_WINDOW / total_count)
    end

    def build_scheduled_payloads(scope, step)
      payloads = []
      offset = 0

      scope.in_batches(of: BATCH_SIZE) do |batch|
        batch.pluck(:id).each_with_index do |prompt_id, idx|
          payloads << [prompt_id, calculate_scheduled_time(offset + idx, step)]
        end
        offset += batch.size
      end

      payloads
    end

    def schedule_prompt_jobs(payloads)
      payloads.each { |prompt_id, time| PromptProcessorJob.perform_at(time, prompt_id, @search.user_id) }
    end

    def calculate_scheduled_time(index, step)
      base_time = @now + (index * step)
      jitter = rand((-step.to_f / 2)..(step.to_f / 2))

      [base_time + jitter, @now].max
    end

    def targets_data
      @targets_data ||= Target.joins(:category)
                              .where(categories: { user_id: @search.user_id })
                              .where(id: @target_ids, is_active: true)
                              .pluck(:id, :domain)
    end

    def prompt_records = @target_ids.blank? ? global_prompt_record : target_prompt_records

    def cleanup_obsolete_prompts = @target_ids.blank? ? cleanup_global_prompts : cleanup_target_prompts

    def cleanup_global_prompts
      @search.prompts.where.not(target_id: nil).delete_all
      @search.prompts.where(target_id: nil).where.not(full_query_text: @search.query_conditions).destroy_all
    end

    def cleanup_target_prompts
      active_targets = targets_data.to_h
      @search.prompts.find_each { |p| p.destroy if obsolete_target_prompt?(p, active_targets) }
    end

    def obsolete_target_prompt?(prompt, active_targets)
      return true if prompt.target_id.nil? || !active_targets.key?(prompt.target_id)

      prompt.full_query_text != "site:#{active_targets[prompt.target_id]} #{@search.query_conditions}"
    end

    def global_prompt_record = [base_prompt_attributes(nil, @search.query_conditions)]

    def target_prompt_records
      targets_data.map { |id, domain| base_prompt_attributes(id, "site:#{domain} #{@search.query_conditions}") }
    end

    def base_prompt_attributes(target_id, query_text)
      { search_id: @search.id, target_id: target_id, full_query_text: query_text,
        status: "pending", created_at: @now, updated_at: @now }
    end

    def broadcast_live_status(message)
      Turbo::StreamsChannel.broadcast_render_to(
        @search, :results, template: "searches/update_status", assigns: { message: message }
      )
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::Activator] Live status broadcast failed: #{e.message}")
    end
  end
end
