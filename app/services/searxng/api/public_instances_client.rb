# frozen_string_literal: true

module Searxng
  module Api
    class PublicInstancesClient < BaseClient
      PUBLIC_POOL_KEY = "searxng:public_pool"
      DATA_URL = "https://searx.space/data/instances.json"
      CACHE_TTL = 3600
      BASE_JITTER = 1..3

      private

      def logger_tag = "Searxng::Api::PublicInstancesClient"

      def max_retries_count
        count = @redis.llen(PUBLIC_POOL_KEY).to_i
        count.positive? ? count : MAX_RETRIES
      end

      def perform_request(instance)
        apply_jitter if defined?(@current_attempts) && @current_attempts.positive?
        @current_attempts = (@current_attempts || 0) + 1

        super
      rescue StandardError => e
        Rails.logger.warn("[#{logger_tag}] Network error for #{instance}: #{e.message}")

        Struct.new(:code, :body).new(503, "")
      end

      def apply_jitter
        delay = rand(BASE_JITTER)
        Kernel.sleep(delay)
      end

      def initialize_pool
        return if redis_key_exists?(PUBLIC_POOL_KEY)

        response = HTTParty.get(DATA_URL, timeout: 10)
        return unless response.code == 200

        valid_urls = fetch_valid_public_urls(response.body)
        if valid_urls.any?
          @redis.rpush(PUBLIC_POOL_KEY, valid_urls.shuffle)
          @redis.expire(PUBLIC_POOL_KEY, CACHE_TTL)
        end
      rescue StandardError => e
        Rails.logger.error("[#{logger_tag}] Failed to load public instances: #{e.message}")
      end

      def fetch_valid_public_urls(body)
        data = JSON.parse(body)
        instances = data["instances"] || {}

        instances.select { |url, conf| valid_instance?(url, conf) }.keys
      rescue JSON::ParserError
        []
      end

      def valid_instance?(url, conf)
        return false if url.to_s.include?(".onion")

        conf.dig("http", "status_code") == 200 && conf.dig("http", "error").nil?
      end

      def next_available_instance
        instance = @redis.rpoplpush(PUBLIC_POOL_KEY, PUBLIC_POOL_KEY)
        return nil if instance.blank?

        return find_next_alive_instance if redis_key_exists?("#{REDIS_DEAD_PREFIX}#{instance}")

        instance
      end

      def find_next_alive_instance
        total_instances = @redis.llen(PUBLIC_POOL_KEY)
        total_instances.times do
          instance = @redis.rpoplpush(PUBLIC_POOL_KEY, PUBLIC_POOL_KEY)
          return instance unless redis_key_exists?("#{REDIS_DEAD_PREFIX}#{instance}")
        end
        nil
      end
    end
  end
end
