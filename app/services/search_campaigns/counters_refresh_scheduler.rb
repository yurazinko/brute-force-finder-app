# frozen_string_literal: true

module SearchCampaigns
  class CountersRefreshScheduler
    DEBOUNCE = 1.second
    LOCK_TTL = 30
    GENERATION_TTL = 1.hour

    RELEASE_LOCK_LUA = <<~LUA
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        return redis.call('DEL', KEYS[1])
      else
        return 0
      end
    LUA

    FINALIZE_LUA = <<~LUA
      if redis.call('GET', KEYS[1]) ~= ARGV[1] then
        return -1
      end
      if (redis.call('GET', KEYS[2]) or '0') ~= ARGV[2] then
        return 1
      end
      redis.call('DEL', KEYS[1])
      return 0
    LUA

    class << self
      def schedule(search)
        key = lock_key(search.id)
        generation = generation_key(search.id)
        token = SecureRandom.hex(16)

        acquired = Sidekiq.redis do |redis|
          redis.incr(generation)
          redis.expire(generation, GENERATION_TTL.to_i)
          redis.set(key, token, nx: true, ex: LOCK_TTL)
        end

        return false unless acquired

        SearchCampaigns::CountersRefreshJob.perform_in(
          DEBOUNCE, search.id, search.user_id, token
        )
        true
      rescue StandardError
        # Only delete the lock if this scheduler call owns it.
        release_lock(search.id, token) if token.present?
        raise
      end

      def lock_key(search_id) = "search_counters_refresh:lock:#{search_id}"

      def generation_key(search_id) = "search_counters_refresh:generation:#{search_id}"

      def release_lock(search_id, token)
        Sidekiq.redis do |redis|
          redis.eval(RELEASE_LOCK_LUA, 1, lock_key(search_id), token.to_s)
        end
      end

      # Detect updates that arrived while counters were being computed. The Lua
      # compare-and-delete closes the race between checking the generation and
      # releasing the debounce lock.
      def finalize(search_id, token, generation)
        result = Sidekiq.redis do |redis|
          redis.eval(
            FINALIZE_LUA,
            2,
            lock_key(search_id),
            generation_key(search_id),
            token.to_s,
            generation.to_s
          )
        end

        { -1 => :lost_lock, 0 => :released, 1 => :dirty }.fetch(result.to_i, :lost_lock)
      end
    end
  end
end
