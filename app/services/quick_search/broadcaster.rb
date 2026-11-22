# frozen_string_literal: true

module QuickSearch
  class Broadcaster
    class << self
      def status(token, quick_search)
        Turbo::StreamsChannel.broadcast_render_to(
          token,
          :results,
          template: "quick_searches/update_status",
          assigns: { quick_search: quick_search, token: token }
        )
      rescue StandardError => e
        Rails.logger.error("[QuickSearch::Broadcaster] Status broadcast failed: #{e.message}")
      end

      def result(token, result)
        Turbo::StreamsChannel.broadcast_append_to(
          token,
          :results,
          target: "quick_search_results",
          partial: "results/result_card",
          locals: { result: result, quick_search: true }
        )
      rescue StandardError => e
        Rails.logger.error("[QuickSearch::Broadcaster] Result broadcast failed: #{e.message}")
      end

      def replace_result(token, result)
        Turbo::StreamsChannel.broadcast_replace_to(
          token,
          :results,
          target: "quick_result_#{result.url_hash}",
          partial: "results/result_card",
          locals: { result: result, quick_search: true }
        )
      rescue StandardError => e
        Rails.logger.error("[QuickSearch::Broadcaster] Result update broadcast failed: #{e.message}")
      end
    end
  end
end
