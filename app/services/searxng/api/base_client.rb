# frozen_string_literal: true

require "httparty"

module Searxng
  module Api
    class BaseClient
      include HTTParty

      TIMEOUT = 12
      MAX_RETRIES = 3
      CIRCUIT_BREAKER_TTL = 900
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

        while attempts < max_retries_count
          instance = next_available_instance
          return { success: false, error: "All SearXNG instances are currently dead" } if instance.blank?

          result = perform_request(instance)

          res_hash = result.respond_to?(:to_h) ? result.to_h : result

          return res_hash if res_hash.is_a?(Hash) && res_hash[:success]

          attempts += 1
        end

        { success: false, error: "Failed after #{max_retries_count} attempts across multiple instances" }
      end

      private

      def initialize_pool = raise(NotImplementedError)

      def next_available_instance = raise(NotImplementedError)

      def logger_tag = raise(NotImplementedError)

      def perform_request(instance)
        response = self.class.get("#{instance}/search", query_options)
        handle_response(response, instance)
      rescue HTTParty::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error => e
        Rails.logger.warn("[#{logger_tag}] Instance #{instance} failed: #{e.message}. Triaging next.")
        triaged_as_dead(instance)
        { success: false, error: e.message }
      end

      def redis_key_exists?(key)
        res = @redis.exists?(key)
        res.is_a?(Integer) ? res.positive? : res
      end

      def triaged_as_dead(instance)
        @redis.setex("#{REDIS_DEAD_PREFIX}#{instance}", CIRCUIT_BREAKER_TTL, "dead")
      end

      def handle_response(response, instance)
        case response.code
        when 200 then parse_urls(response.body, instance)
        when 429 then handle_rate_limit(instance)
        else { success: false, error: "HTTP #{response.code}" }
        end
      end

      def handle_rate_limit(instance)
        Rails.logger.error("[#{logger_tag}] Rate limit (429) hit on #{instance}. Triaging.")
        triaged_as_dead(instance)
        { success: false, error: "Rate limit" }
      end

      def query_options
        {
          headers: {
            "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
                            "AppleWebKit/537.36 (KHTML, like Gecko) " \
                            "Chrome/120.0.0.0 Safari/537.36",
            "Accept" => "text/html,application/json,application/xhtml+xml",
            "Accept-Language" => "en-US,en;q=0.9"
          },
          query: base_params
        }
      end

      def base_params
        params = { q: @query, format: "json", pageno: 1,
                   engines: "google,duckduckgo,bing,brave,qwant,startpage,mojeek" }
        params[:time_range] = @time_range if @time_range.present?
        params
      end

      def parse_urls(response_body, instance)
        data = JSON.parse(response_body)
        Rails.logger.info("===================== SearXNG Response from #{instance}: #{data} ==========================")
        return { success: false, error: "Engine Error: #{data['error']}" } if data["error"]

        { success: true, data: extract_results(data), failed_engines: data["unresponsive_engines"] || [] }
      rescue JSON::ParserError => e
        Rails.logger.error("[#{logger_tag}] Malformed JSON from #{instance}: #{e.message}")
        { success: false, error: "Malformed JSON" }
      end

      def extract_results(data)
        raw_results = data["results"] || []
        mapped = raw_results.map { |hash| hash.slice("url", "title", "content") }
        mapped.uniq! { |hash| hash["url"] }
        mapped
      end

      def max_retries_count = MAX_RETRIES
    end
  end
end
