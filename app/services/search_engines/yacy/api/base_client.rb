# frozen_string_literal: true

module SearchEngines
  module Yacy
    module Api
      class BaseClient < ::BaseApiClient
        REDIS_DEAD_PREFIX = "yacy:dead:"

        private

        def provider_name = "YaCy"

        def redis_dead_prefix = REDIS_DEAD_PREFIX

        def max_timeout = 12

        def query_options
          {
            timeout: max_timeout,
            query: {
              query: build_formatted_query,
              maximumRecords: 60,
              resource: "global",
              meanCount: 0,
              maximumTime: 10,
              verify: "ifexist",
              strictContentDom: false
            }
          }
        end

        def build_formatted_query
          formatted_query = @query.to_s.dup

          formatted_query.gsub!("&quot;", '"')

          formatted_query.gsub!(/\bsite:(\S+)/i) do
            raw_site = ::Regexp.last_match(1).sub(%r{^https?://}, "")
            clean_host = raw_site.split("/").first
            "site:#{clean_host}"
          end

          return formatted_query if time_frame_start_date.nil?

          formatted_date = time_frame_start_date.strftime("%Y/%m/%d")
          "#{formatted_query} from:#{formatted_date} /date"
        end

        def time_frame_start_date
          case @options[:time_range].to_s
          when "day"   then 1.day.ago
          when "week"  then 1.week.ago
          when "month" then 1.month.ago
          when "year"  then 1.year.ago
          end
        end

        def perform_request(instance)
          response = self.class.get("#{instance}/yacysearch.json", query_options)
          handle_response(response, instance)
        rescue StandardError => e
          Rails.logger.warn("[#{logger_tag}] YaCy instance #{instance} failed: #{e.message}")
          triaged_as_dead(instance)
          { success: false, error: e.message }
        end

        def handle_response(response, _instance)
          return { success: false, error: "HTTP #{response.code}" } unless response.code == 200

          data = JSON.parse(response.body)

          Rails.logger.info("============================== Yacy Response: #{data} ===================================")
          channels = data.dig("channels", 0, "items") || []

          results = channels.map do |item|
            {
              "url" => item["link"],
              "title" => item["title"],
              "content" => item["description"]
            }
          end

          { success: true, data: results, failed_engines: [] }
        end
      end
    end
  end
end
