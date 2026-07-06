# frozen_string_literal: true

module Searxng
  module Api
    class TorClient < BaseClient
      REDIS_POOL_KEY = "searxng:pool"

      private

      def logger_tag = "Searxng::Api::TorClient"

      def initialize_pool
        return if redis_key_exists?(REDIS_POOL_KEY)

        urls = ENV.fetch("SEARXNG_URLS", "http://searxng_1:8080").split(",")
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

      def query_options
        random_auth = SecureRandom.hex(8)
        super.merge(
          socks_username: random_auth,
          socks_password: random_auth
        )
      end
    end
  end
end
