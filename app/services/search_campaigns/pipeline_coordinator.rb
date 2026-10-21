# frozen_string_literal: true

module SearchCampaigns
  class PipelineCoordinator
    def initialize(prompt)
      @prompt = prompt
      @search = prompt.search
    end

    def success!
      @prompt.update!(status: "success")
    end

    def fail!(reason)
      @prompt.update!(status: "failed")
      Rails.logger.error("[PipelineCoordinator] Prompt##{@prompt.id} failed: #{reason}")
    end

    def evaluate_completion!
      remaining_prompts_count = @search.prompts
                                       .left_joins(:target)
                                       .where(status: %w[pending active])
                                       .where("prompts.target_id IS NULL OR targets.is_active = ?", true)
                                       .count

      return unless remaining_prompts_count.zero?

      @search.update!(status: "completed")
    end
  end
end
