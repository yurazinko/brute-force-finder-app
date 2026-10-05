# frozen_string_literal: true

module SearchEngines
  module Degoog
    module Api
      class DefaultClient < BaseClient
        REDIS_POOL_KEY = "degoog:pool"

        private

        def logger_tag = "Degoog::Api::Client"

        def initialize_pool
          return if redis_key_exists?(REDIS_POOL_KEY)

          urls = ENV.fetch("DEGOOG_URLS", "http://degoog:4444").split(",")
          @redis.rpush(REDIS_POOL_KEY, urls.shuffle) if urls.any?
        end

        def next_available_instance
          instance = @redis.rpoplpush(REDIS_POOL_KEY, REDIS_POOL_KEY)
          return nil if instance.blank?

          return find_next_alive_instance if redis_key_exists?("#{REDIS_DEAD_PREFIX}#{instance}")

          instance
        end

        def find_next_alive_instance
          total_instances = @redis.llen(REDIS_POOL_KEY)
          total_instances.times do
            instance = @redis.rpoplpush(REDIS_POOL_KEY, REDIS_POOL_KEY)
            return instance unless redis_key_exists?("#{REDIS_DEAD_PREFIX}#{instance}")
          end
          nil
        end
      end
    end
  end
end
