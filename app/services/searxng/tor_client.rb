# frozen_string_literal: true

require "httparty"
require "securerandom"

module Searxng
  class TorClient
    include HTTParty

    TIMEOUT = 12
    MAX_RETRIES = 3
    CIRCUIT_BREAKER_TTL = 900
    REDIS_POOL_KEY = "searxng:pool"
    REDIS_DEAD_PREFIX = "searxng:dead:"

    default_timeout TIMEOUT

    def self.search(query, options = {}) = new(query, options).execute

    def initialize(query, options = {})
      @query = query
      @time_range = options[:time_range]
      @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1"))
      initialize_pool
    end

    def execute
      return { success: true, data: [] } if @query.blank?

      attempts = 0

      while attempts < MAX_RETRIES
        instance = next_available_instance
        return { success: false, error: "All SearXNG instances are currently dead" } if instance.blank?

        result = perform_request(instance)
        return result if result[:success]

        attempts += 1
      end

      { success: false, error: "Failed after #{MAX_RETRIES} attempts across multiple instances" }
    end

    private

    def perform_request(instance)
      response = self.class.get("#{instance}/search", query_options)
      handle_response(response, instance)
    rescue HTTParty::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error => e
      Rails.logger.warn("[Searxng::TorClient] Instance #{instance} failed: #{e.message}. Triaging next.")
      triaged_as_dead(instance)
      { success: false, error: e.message }
    end

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

    def redis_key_exists?(key)
      res = @redis.exists?(key)
      res.is_a?(Integer) ? res.positive? : res
    end

    def triaged_as_dead(instance) = @redis.setex("#{REDIS_DEAD_PREFIX}#{instance}", CIRCUIT_BREAKER_TTL, "dead")

    def handle_response(response, instance)
      case response.code
      when 200
        parse_urls(response.body, instance)
      when 429
        Rails.logger.error("[Searxng::TorClient] Rate limit (429) hit on #{instance}. Triaging.")
        triaged_as_dead(instance)
        { success: false, error: "Rate limit" }
      else
        { success: false, error: "SearXNG returned HTTP #{response.code}" }
      end
    end

    def query_options
      random_auth = SecureRandom.hex(8)

      { headers: { "User-Agent" => "BruteForceFinderApp/1.0 (Ruby on Rails; Scraping Pipeline)" },
        query: base_params,
        socks_username: random_auth,
        socks_password: random_auth }
    end

    def base_params
      params = { q: @query, format: "json", pageno: 1, engines: "google,duckduckgo,bing,brave,qwant,startpage,mojeek" }
      params[:time_range] = @time_range if @time_range.present?
      params
    end

    def parse_urls(response_body, instance)
      data = JSON.parse(response_body)
      log_response(data)
      return { success: false, error: "SearXNG Engine Error: #{data['error']}" } if data["error"]

      { success: true, data: extract_results(data), failed_engines: data["unresponsive_engines"] || [] }
    rescue JSON::ParserError => e
      Rails.logger.error("[Searxng::TorClient] Malformed JSON from #{instance}: #{e.message}")
      { success: false, error: "Malformed JSON" }
    end

    def log_response(data) = Rails.logger.info("===================== SearXNG Response: #{data} ======================")

    def extract_results(data)
      raw_results = data["results"] || []
      mapped = raw_results.map { |hash| hash.slice("url", "title", "content") }
      mapped.uniq! { |hash| hash["url"] }
      mapped
    end
  end
end
