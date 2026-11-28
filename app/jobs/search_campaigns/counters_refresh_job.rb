# frozen_string_literal: true

module SearchCampaigns
  class CountersRefreshJob
    include Sidekiq::Job
    include Rls::SidekiqSupport

    sidekiq_options queue: :default, retry: 5

    def perform(search_id, user_id, lock_token)
      return unless CountersRefreshScheduler.ensure_lock_ownership(search_id, lock_token)

      generation = current_generation(search_id)
      search = find_search(search_id, user_id)
      unless search
        CountersRefreshScheduler.release_lock(search_id, lock_token)
        return
      end

      broadcast_counters(search)
      reschedule_if_dirty(search_id, user_id, lock_token, generation)
    end

    private

    def current_generation(search_id)
      Sidekiq.redis do |redis|
        redis.get(CountersRefreshScheduler.generation_key(search_id)).to_s.presence || "0"
      end
    end

    def find_search(search_id, user_id)
      Search.find_by(id: search_id, user_id: user_id)
    end

    def broadcast_counters(search)
      counts = Results::Counters.calculate_filtered(search.results, counter_filters(search), search)
      LifecycleNotifier.broadcast_counters(search, counts)
    end

    def counter_filters(search)
      {
        status: "unread",
        time_frame: search.time_frame,
        sort: Results::Query::DEFAULT_SORT,
        show_acknowledged: search.show_acknowledged,
        show_less_relevant: false
      }
    end

    def reschedule_if_dirty(search_id, user_id, lock_token, generation)
      state = CountersRefreshScheduler.finalize(search_id, lock_token, generation)
      return unless state == :dirty

      self.class.perform_in(CountersRefreshScheduler::DEBOUNCE, search_id, user_id, lock_token)
    end
  end
end
