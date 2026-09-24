# frozen_string_literal: true

module SearchCampaigns
  class LifecycleNotifier
    def self.broadcast_metrics(search, counts)
      new(search).broadcast_metrics(counts)
    end

    def self.broadcast_status(search, message = nil)
      new(search).broadcast_status(message)
    end

    def initialize(search)
      @search = search
    end

    def broadcast_metrics(counts)
      broadcast_counters(counts)
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
  end
end
