# frozen_string_literal: true

module SearchCampaigns
  class CountersRefreshJob
    include Sidekiq::Job
    include Rls::SidekiqSupport

    sidekiq_options queue: :default, retry: 5

    def perform(search_id, user_id, lock_token)
      generation = Sidekiq.redis do |redis|
        redis.get(CountersRefreshScheduler.generation_key(search_id)).to_s
      end

      search = Search.find_by(id: search_id, user_id: user_id)
      unless search
        CountersRefreshScheduler.release_lock(search_id, lock_token)
        return
      end

      counts = Results::Counters.calculate_filtered(
        search.results,
        {
          status: "unread",
          time_frame: search.time_frame,
          sort: Results::Query::DEFAULT_SORT,
          show_acknowledged: search.show_acknowledged,
          show_less_relevant: false
        },
        search
      )
      LifecycleNotifier.broadcast_counters(search, counts)

      state = CountersRefreshScheduler.finalize(search_id, lock_token, generation)
      return unless state == :dirty

      self.class.perform_in(
        CountersRefreshScheduler::DEBOUNCE, search_id, user_id, lock_token
      )
    end
  end
end
