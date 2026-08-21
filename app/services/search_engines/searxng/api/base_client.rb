# frozen_string_literal: true

module SearchEngines
  module Searxng
    module Api
      class BaseClient < ::BaseApiClient
        REDIS_DEAD_PREFIX = "searxng:dead:"

        private

        def provider_name = "SearXNG"

        def redis_dead_prefix = REDIS_DEAD_PREFIX

        def perform_request(instance)
          response = self.class.get("#{instance}/search", query_options)
          handle_response(response, instance)
        rescue HTTParty::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error => e
          Rails.logger.warn("[#{logger_tag}] Instance #{instance} failed: #{e.message}. Triaging next.")
          triaged_as_dead(instance)
          { success: false, error: e.message }
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
          params = { q: build_formatted_query, format: "json", pageno: 1,
                     engines: "google,duckduckgo,bing,brave,qwant,startpage,mojeek" }
          params[:time_range] = @time_range if @time_range.present?
          params
        end

        def build_formatted_query
          formatted_query = @query.to_s.dup

          formatted_query.gsub!("&quot;", '"')

          formatted_query.gsub!(/\bsite:(\S+)/i) do
            raw_site = ::Regexp.last_match(1).sub(%r{^https?://}, "")
            clean_host = raw_site.split("/").first
            "site:#{clean_host}"
          end
        end

        def parse_urls(response_body, instance)
          data = JSON.parse(response_body)
          Rails.logger.info("==================== SearXNG Response from #{instance}: #{data} =========================")
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
      end
    end
  end
end
