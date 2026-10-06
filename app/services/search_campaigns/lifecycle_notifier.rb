# frozen_string_literal: true

module SearchCampaigns
  class LifecycleNotifier
    def self.broadcast_metrics(search, counts, new_results: [])
      new(search).broadcast_metrics(counts, new_results: new_results)
    end

    def self.broadcast_status(search, message = nil)
      new(search).broadcast_status(message)
    end

    def initialize(search)
      @search = search
    end

    def broadcast_metrics(counts, new_results: [])
      broadcast_counters(counts)
      broadcast_new_results(new_results) if new_results.present?
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::LifecycleNotifier] Metrics broadcast failed: #{e.message}")
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
        @search,
        :results,
        target: "search_lifecycle_status",
        html: ApplicationController.render(
          partial: "searches/status_content",
          locals: { search: @search }
        )
      )
    end

    def broadcast_message_update(message)
      Turbo::StreamsChannel.broadcast_render_to(
        @search,
        :results,
        template: "searches/update_status",
        assigns: { message: message }
      )
    end

    def broadcast_counters(counts)
      targets = {
        "counter_unread" => counts.unread,
        "counter_interesting" => counts.interesting,
        "counter_watched" => counts.watched,
        "counter_garbage" => counts.garbage
      }

      targets.each do |target_id, value|
        Turbo::StreamsChannel.broadcast_update_to(
          @search,
          :results,
          target: target_id,
          html: value.to_i.to_s
        )
      end
    end

    def broadcast_new_results(new_results)
      new_results.each do |result|
        Turbo::StreamsChannel.broadcast_prepend_to(
          @search,
          :results,
          target: "results_pool_list",
          partial: "results/result_card",
          locals: { result: result }
        )
      end
    end
  end
end
