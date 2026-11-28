# frozen_string_literal: true

module SearchCampaigns
  class CountersRefreshScheduler
    DEBOUNCE = 1.second
    LOCK_TTL = 120
    GENERATION_TTL = 7.days
    FINALIZE_SCRIPT = <<~LUA
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
        token = SecureRandom.hex(16)
        return false unless acquire_lock(search.id, token)

        enqueue_refresh(search, token)
      rescue StandardError
        release_lock(search.id, token) if token.present?
        raise
      end

      def lock_key(search_id) = "search_counters_refresh:lock:#{search_id}"

      def generation_key(search_id) = "search_counters_refresh:generation:#{search_id}"

      def release_lock(search_id, token)
        Sidekiq.redis do |redis|
          redis.call(
            "EVAL",
            "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end",
            "1",
            lock_key(search_id),
            token.to_s
          )
        end
      end

      # Sidekiq retries may start after the short-lived debounce lock expired.
      # Reacquire only when it is absent; never overwrite a newer scheduler token.
      def ensure_lock_ownership(search_id, token)
        Sidekiq.redis do |redis|
          key = lock_key(search_id)
          current = redis.get(key)
          if current == token.to_s
            redis.expire(key, LOCK_TTL)
            true
          elsif current.nil?
            !redis.set(key, token.to_s, nx: true, ex: LOCK_TTL).nil?
          else
            false
          end
        end
      end

      # Detect updates that arrived while counters were being computed. The Lua
      # compare-and-delete closes the race between checking the generation and
      # releasing the debounce lock.
      def finalize(search_id, token, generation)
        result = run_finalize_script(search_id, token, generation)
        { -1 => :lost_lock, 0 => :released, 1 => :dirty }.fetch(result.to_i, :lost_lock)
      end

      private

      def run_finalize_script(search_id, token, generation)
        Sidekiq.redis do |redis|
          redis.call(
            "EVAL", FINALIZE_SCRIPT, "2", lock_key(search_id), generation_key(search_id),
            token.to_s, generation.to_s
          )
        end
      end

      def acquire_lock(search_id, token)
        Sidekiq.redis do |redis|
          redis.incr(generation_key(search_id))
          redis.expire(generation_key(search_id), GENERATION_TTL.to_i)
          redis.set(lock_key(search_id), token, nx: true, ex: LOCK_TTL)
        end
      end

      def enqueue_refresh(search, token)
        SearchCampaigns::CountersRefreshJob.perform_in(DEBOUNCE, search.id, search.user_id, token)
        true
      end
    end
  end
end
