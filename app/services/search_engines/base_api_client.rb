# frozen_string_literal: true

require "httparty"
require "connection_pool"

module SearchEngines
  REDIS_POOL = ConnectionPool::Wrapper.new(size: 10, timeout: 5) do
    Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1"))
  end

  class BaseApiClient
    include HTTParty

    TIMEOUT = 12
    MAX_RETRIES = 3
    CIRCUIT_BREAKER_TTL = 900
    POOL_SYNC_TTL = 300

    default_timeout TIMEOUT

    def self.search(query, options = {}) = new(query, options).execute

    def initialize(query, options = {})
      @query = query
      @options = options
      @time_range = options[:time_range]
      @redis = REDIS_POOL
      initialize_pool
    end

    def execute
      return { success: true, data: [] } if @query.blank?

      attempts = 0

      while attempts < max_retries_count
        instance = next_available_instance
        return { success: false, error: "All #{provider_name} instances are currently dead" } if instance.blank?

        result = perform_request(instance)
        res_hash = result.respond_to?(:to_h) ? result.to_h : result

        return res_hash if res_hash.is_a?(Hash) && res_hash[:success]

        attempts += 1
      end

      { success: false, error: "Failed after #{max_retries_count} attempts across multiple instances" }
    end

    private

    def initialize_pool
      urls = ENV.fetch(pool_env_var, pool_default_urls).split(",").map(&:strip).compact_blank
      return if urls.empty?

      sync_key = "#{pool_redis_key}:synced"
      return if redis_key_exists?(sync_key)

      lock_key = "#{pool_redis_key}:lock"
      return unless @redis.set(lock_key, "1", nx: true, ex: 10)

      begin
        @redis.multi do |multi|
          multi.del(pool_redis_key)
          multi.rpush(pool_redis_key, urls.shuffle)
          multi.setex(sync_key, POOL_SYNC_TTL, "1")
        end
      ensure
        @redis.del(lock_key)
      end
    end

    def next_available_instance
      instance = @redis.lmove(pool_redis_key, pool_redis_key, "RIGHT", "LEFT")
      return nil if instance.blank?

      return find_next_alive_instance if redis_key_exists?("#{redis_dead_prefix}#{instance}")

      instance
    end

    def find_next_alive_instance
      total_instances = @redis.llen(pool_redis_key)
      total_instances.times do
        instance = @redis.lmove(pool_redis_key, pool_redis_key, "RIGHT", "LEFT")
        return instance unless redis_key_exists?("#{redis_dead_prefix}#{instance}")
      end
      nil
    end

    def pool_redis_key = raise(NotImplementedError)

    def pool_env_var = raise(NotImplementedError)

    def pool_default_urls = raise(NotImplementedError)

    def logger_tag = raise(NotImplementedError)

    def provider_name = raise(NotImplementedError)

    def redis_dead_prefix = raise(NotImplementedError)

    def perform_request(_instance) = raise(NotImplementedError)

    def redis_key_exists?(key)
      res = @redis.exists?(key)
      res.is_a?(Integer) ? res.positive? : res
    end

    def triaged_as_dead(instance)
      @redis.setex("#{redis_dead_prefix}#{instance}", CIRCUIT_BREAKER_TTL, "dead")
    end

    def max_retries_count = MAX_RETRIES
  end
end
