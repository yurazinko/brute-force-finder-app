# frozen_string_literal: true

module SearchCampaigns
  class LifecycleNotifier
    def self.broadcast_metrics(search, counts, new_results: [])
      broadcast_new_results(search, new_results)
      broadcast_counters(search, counts)
    end

    def self.broadcast_new_results(search, new_results)
      new(search).broadcast_new_results(new_results)
    end

    def self.broadcast_counters(search, counts)
      new(search).broadcast_counters(counts)
    end

    def self.broadcast_status(search, message = nil)
      new(search).broadcast_status(message)
    end

    def initialize(search)
      @search = search
    end

    def broadcast_new_results(new_results)
      result_ids = Array(new_results).filter_map(&:id)
      return if result_ids.empty?

      records = Result.includes(:search).where(id: result_ids).index_by(&:id)
      persisted_results = result_ids.filter_map { |id| records[id] }
      return if persisted_results.empty?

      Turbo::StreamsChannel.broadcast_render_to(
        @search, :results,
        template: "searches/broadcast_new_results",
        assigns: { search: @search, new_results: persisted_results }
      )
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::LifecycleNotifier] Result batch broadcast failed: #{e.message}")
    end

    def broadcast_counters(counts)
      Turbo::StreamsChannel.broadcast_render_to(
        @search, :results,
        template: "searches/broadcast_counters",
        assigns: { counts: counts }
      )
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::LifecycleNotifier] Counter broadcast failed: #{e.message}")
    end

    def broadcast_status(message = nil)
      broadcast_status_content
      broadcast_message_update(message) if message
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::LifecycleNotifier] Status broadcast failed: #{e.message}")
    end

    private

    def broadcast_status_content
      Turbo::StreamsChannel.broadcast_update_to(
        @search, :results,
        target: "search_lifecycle_status",
        html: ApplicationController.render(
          partial: "searches/status_content", locals: { search: @search }
        )
      )
    end

    def broadcast_message_update(message)
      Turbo::StreamsChannel.broadcast_render_to(
        @search, :results,
        template: "searches/update_status",
        assigns: { message: message }
      )
    end
  end
end
