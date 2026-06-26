# frozen_string_literal: true

module SearchCampaigns
  class LifecycleNotifier
    def self.broadcast_metrics(search, db_counts, total_cached)
      new(search).broadcast_metrics(db_counts, total_cached)
    end

    def self.broadcast_status(search, message = nil)
      new(search).broadcast_status(message)
    end

    def initialize(search)
      @search = search
    end

    def broadcast_metrics(db_counts, total_cached)
      @total_cached = total_cached

      broadcast_counters(db_counts)
      broadcast_content
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::LifecycleNotifier] Metrics broadcast failed: #{e.message}")
    end

    def broadcast_status(message = nil)
      Turbo::StreamsChannel.broadcast_update_to(
        @search, :results,
        target: "search_lifecycle_status",
        html: ApplicationController.render(partial: "searches/status_content", locals: { search: @search })
      )

      if message
        Turbo::StreamsChannel.broadcast_render_to(
          @search, :results,
          template: "searches/update_status",
          assigns: { message: message }
        )
      end
    rescue StandardError => e
      Rails.logger.error("[SearchCampaigns::LifecycleNotifier] Status broadcast failed: #{e.message}")
    end

    private

    def broadcast_counters(db_counts)
      counts = {
        all_clean: db_counts.except("garbage").values.sum,
        unread: db_counts["unread"] || 0,
        interesting: db_counts["interesting"] || 0,
        watched: db_counts["watched"] || 0,
        garbage: db_counts["garbage"] || 0
      }

      targets(counts).each do |target_id, value|
        Turbo::StreamsChannel.broadcast_update_to(@search, :results, target: target_id, html: (value || 0).to_s)
      end
    end

    def broadcast_content
      latest_results = Result.where(search_id: @search.id).without_garbage.order(created_at: :desc).limit(20)

      Turbo::StreamsChannel.broadcast_replace_to(
        @search, :results,
        target: "results_pool_list",
        partial: "searches/results_pool_content",
        locals: { results: latest_results }
      )
    end

    def targets(counts)
      {
        "counter_all_clean" => counts[:all_clean],
        "counter_unread" => counts[:unread],
        "counter_interesting" => counts[:interesting],
        "counter_watched" => counts[:watched],
        "counter_garbage" => counts[:garbage],
        "results_count" => "Showing: #{@total_cached}"
      }
    end
  end
end
