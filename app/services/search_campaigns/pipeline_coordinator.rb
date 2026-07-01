# frozen_string_literal: true

module SearchCampaigns
  class PipelineCoordinator
    def initialize(prompt)
      @prompt = prompt
      @search = prompt.search
    end

    def activate!
      @prompt.update!(status: "active")
      LifecycleNotifier.broadcast_status(@search)
    end

    def success!
      @prompt.update!(status: "success")
    end

    def fail!(message)
      @prompt.update!(status: "failed", error_message: message)
    end

    def evaluate_completion!
      @search.with_lock do
        return if @search.prompts.active.where(status: %w[active pending]).any?

        @search.update!(status: "completed") unless @search.status == "completed"
        LifecycleNotifier.broadcast_status(@search, "Pipeline finished. All parallel streams synced.")
      end
    end
  end
end
