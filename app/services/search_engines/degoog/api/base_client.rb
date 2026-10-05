# frozen_string_literal: true

module SearchEngines
  module Degoog
    module Api
      class BaseClient < SearchEngines::BaseApiClient
        REDIS_DEAD_PREFIX = "degoog:dead:"
        ENGINES_CACHE_TTL = 1.hour

        FALLBACK_ENGINES = %w[
          degoog-org-official-extensions-bing-engine degoog-org-official-extensions-google-engine
          degoog-org-official-extensions-brave-engine degoog-org-official-extensions-duckduckgo-engine
        ].freeze

        private

        def provider_name = "Degoog"

        def redis_dead_prefix = REDIS_DEAD_PREFIX

        def perform_request(instance)
          url = "#{instance}/api/search"

          response = self.class.post(url, query_options(instance))

          handle_response(response, instance)
        rescue HTTParty::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error => e
          Rails.logger.warn("[#{logger_tag}] Instance #{instance} failed: #{e.message}. Triaging next.")
          triaged_as_dead(instance)
          { success: false, error: e.message }
        end

        def handle_response(response, instance)
          case response.code
          when 200 then parse_response(response.body, instance)
          when 401 then { success: false, error: "Unauthorized: Invalid or missing API key" }
          when 429 then handle_rate_limit(instance)
          else { success: false, error: "HTTP #{response.code}" }
          end
        end

        def handle_rate_limit(instance)
          Rails.logger.error("[#{logger_tag}] Rate limit hit on #{instance}. Triaging.")
          triaged_as_dead(instance)
          { success: false, error: "Rate limit hit" }
        end

        def query_options(instance)
          headers = {
            "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0.0.0 Safari/537.36",
            "Accept" => "application/json",
            "Content-Type" => "application/json",
            "X-Forwarded-For" => "127.0.0.1"
          }

          api_key = ENV.fetch("DEGOOG_API_KEY", nil)
          headers["Authorization"] = "Bearer #{api_key}" if api_key.present?

          { headers: headers, body: payload_json(instance) }
        end

        def payload_json(instance)
          payload = { query: build_formatted_query, type: "web", page: 1, engines: fetch_active_engine_ids(instance) }

          time_param = @options&.dig(:time_range) || "any"
          payload[:time] = time_param if time_param.present?

          payload.to_json
        end

        def fetch_active_engine_ids(instance)
          cache_key = "degoog:engines:#{instance}"

          Rails.cache.fetch(cache_key, expires_in: ENGINES_CACHE_TTL) do
            res = self.class.get("#{instance}/api/extensions?type=engine")
            break FALLBACK_ENGINES unless res.success?

            installed_ids = res.parsed_response["engines"]&.map { |ext| ext["id"] }
            installed_ids.presence || FALLBACK_ENGINES
          end
        rescue StandardError => e
          Rails.logger.warn("[#{logger_tag}] Failed to fetch engines from #{instance}: #{e.message}")
          FALLBACK_ENGINES
        end

        def build_formatted_query
          formatted_query = @query.to_s.dup
          formatted_query.gsub!("&quot;", '"')

          formatted_query.gsub!(/\bsite:(\S+)/i) do
            raw_site = Regexp.last_match(1).sub(%r{^https?://}, "")
            clean_host = raw_site.split("/").first
            "site:#{clean_host}"
          end

          formatted_query.squish
        end

        def parse_response(response_body, instance)
          data = JSON.parse(response_body)

          { success: true, data: extract_results(data) }
        rescue JSON::ParserError => e
          Rails.logger.error("[#{logger_tag}] Malformed JSON from #{instance}: #{e.message}")
          { success: false, error: "Malformed JSON" }
        end

        def extract_results(data)
          results = data["results"] || []

          results.filter_map { |hash| build_result_item(hash) }.uniq { |hash| hash["url"] }
        end

        def build_result_item(hash)
          return if hash["url"].blank?

          { "url" => hash["url"],
            "title" => hash["title"],
            "content" => format_content(hash),
            "engine" => format_engine_label(hash) }
        end

        def format_content(hash)
          [hash["content"], hash["snippet"]].compact_blank.uniq.join(" ").squish
        end

        def format_engine_label(hash)
          sources = hash["sources"]&.map(&:capitalize)&.join(", ")
          source = hash["source"] || sources

          source.present? ? "#{provider_name}/#{source}" : provider_name
        end
      end
    end
  end
end
