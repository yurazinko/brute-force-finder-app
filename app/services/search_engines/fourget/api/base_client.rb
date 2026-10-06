# frozen_string_literal: true

module SearchEngines
  module Fourget
    module Api
      class BaseClient < SearchEngines::BaseApiClient
        REDIS_DEAD_PREFIX = "fourget:dead:"

        private

        def provider_name = "4get"

        def redis_dead_prefix = REDIS_DEAD_PREFIX

        def perform_request(instance)
          url = "#{instance}/api/v1/web"
          response = self.class.get(url, query_options)
          handle_response(response, instance)
        rescue HTTParty::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error => e
          Rails.logger.warn("[#{logger_tag}] Instance #{instance} failed: #{e.message}. Triaging next.")
          triaged_as_dead(instance)
          { success: false, error: e.message }
        end

        def handle_response(response, instance)
          case response.code
          when 200 then parse_response(response.body, instance)
          when 429 then handle_rate_limit(instance)
          else { success: false, error: "HTTP #{response.code}" }
          end
        end

        def handle_rate_limit(instance)
          Rails.logger.error("[#{logger_tag}] Rate limit / Captcha Pass required (429) hit on #{instance}. Triaging.")
          triaged_as_dead(instance)
          { success: false, error: "Rate limit / Pass required" }
        end

        def query_options
          {
            headers: {
              "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
                              "AppleWebKit/537.36 (KHTML, like Gecko) " \
                              "Chrome/120.0.0.0 Safari/537.36",
              "Accept" => "application/json"
            },
            query: base_params
          }
        end

        def base_params
          { s: build_formatted_query }
        end

        def build_formatted_query
          sanitized = sanitize_query(@query)
          return sanitized if sanitized.blank?

          append_time_range(sanitized)
        end

        def append_time_range(query_string)
          start_date = time_frame_start_date
          return query_string unless start_date

          formatted_date = start_date.strftime("%Y-%m-%d")
          "#{query_string} after:#{formatted_date}"
        end

        def time_frame_start_date
          time_range = @time_range.presence.to_s

          return unless %w[day week month year].include?(time_range)

          1.public_send(time_range).ago
        end

        def sanitize_query(raw_query)
          return "" if raw_query.blank?

          query = raw_query.to_s.dup

          query.gsub!(%r{site:([^\s/]+)(/\S*)}) do
            domain = Regexp.last_match(1)
            path_words = Regexp.last_match(2).tr("/", " ")
            "site:#{domain} #{path_words}"
          end

          query.tr!("()", " ")
          query.squish
        end

        def parse_response(response_body, instance)
          data = JSON.parse(response_body)

          return { success: false, error: "4get Error Status: #{data['status']}" } unless data["status"] == "ok"

          {
            success: true,
            data: extract_results(data),
            npt: data["npt"]
          }
        rescue JSON::ParserError => e
          Rails.logger.error("[#{logger_tag}] Malformed JSON from #{instance}: #{e.message}")
          { success: false, error: "Malformed JSON" }
        end

        def extract_results(data)
          web_results = data["web"].presence || []

          raw_results = web_results.filter_map do |hash|
            next if hash["url"].blank?

            {
              "url" => hash["url"],
              "title" => hash["title"],
              "content" => hash["desc"] || hash["description"],
              "engine" => provider_name
            }
          end

          raw_results.uniq { |hash| hash["url"] }
        end
      end
    end
  end
end
