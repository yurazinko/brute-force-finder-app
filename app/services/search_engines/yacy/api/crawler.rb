# frozen_string_literal: true

module SearchEngines
  module Yacy
    module Api
      class Crawler < BaseApiClient
        CRAWLER_ENDPOINT = "/Crawler_p.html"
        REDIS_DEAD_PREFIX = "yacy:dead:"

        private

        def redis_dead_prefix = REDIS_DEAD_PREFIX

        def initialize_pool
          nodes = ENV.fetch("YACY_PEER_URLS", "http://localhost:8090").split(",")
          @pool = nodes.map(&:strip)
        end

        def next_available_instance
          alive_node = @pool.find { |instance| !redis_key_exists?("#{redis_dead_prefix}#{instance}") }
          return alive_node if alive_node.present?

          Rails.logger.warn("#{logger_tag} All nodes are marked as dead! Fallback to standard pool node.")
          @pool.first
        end

        def provider_name
          "YaCy Crawler"
        end

        def logger_tag
          "[YACY_CRAWLER]"
        end

        def perform_request(instance)
          url = "#{instance}#{CRAWLER_ENDPOINT}"

          query_params = build_crawler_params

          response = self.class.post(
            url,
            body: query_params,
            digest_auth: auth_credentials,
            headers: { "Content-Type" => "application/x-www-form-urlencoded" },
            timeout: TIMEOUT
          )

          handle_response(response, instance)
        rescue StandardError => e
          Rails.logger.error("#{logger_tag} Connection failure on #{instance}: #{e.message}")
          triaged_as_dead(instance)
          { success: false, error: e.message }
        end

        def build_crawler_params # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
          {
            "crawlingstart" => "Neuen Crawl starten",
            "crawlingMode" => @options[:mode] || "url",
            "crawlingURL" => @query,
            "crawlingDepth" => (@options[:depth] || 3).to_s,
            "range" => @options[:range] || "domain",
            "mustmatch" => @options[:mustmatch] || ".*",
            "mustnotmatch" => @options[:mustnotmatch] || "",
            "crawlingQ" => @options[:crawl_query_urls] ? "on" : "off",
            "crawlingDomMaxPages" => (@options[:max_pages] || 1000).to_s,
            "recrawl" => @options[:recrawl] || "nodoubles",
            "reloadIfOlderNumber" => (@options[:reload_older_num] || 1).to_s,
            "reloadIfOlderUnit" => @options[:reload_older_unit] || "day",
            "indexText" => @options[:index_text] == false ? "off" : "on",
            "indexMedia" => @options[:index_media] ? "on" : "off",
            "xsstopw" => @options[:use_stopwords] == false ? "off" : "on",
            "collection" => @options[:collection] || "default",
            "crawlOrder" => "off",
            "agentName" => @options[:agent_name] || "YaCy Internet (cautious)"
          }.tap do |params|
            params["sitemapURL"] = @options[:sitemap_url] if @options[:mode] == "sitemap"
          end
        end

        def auth_credentials
          {
            username: ENV.fetch("YACY_ADMIN_USER"),
            password: ENV.fetch("YACY_ADMIN_PASSWORD")
          }
        end

        def handle_response(response, instance)
          if response.success?
            Rails.logger.info("#{logger_tag} Successfully dispatched crawl for #{@query} to #{instance}")
            { success: true, data: { instance: instance, status: response.code } }
          else
            Rails.logger.warn("#{logger_tag} Instance #{instance} returned error status #{response.code}")
            triaged_as_dead(instance)
            { success: false, error: "HTTP #{response.code}" }
          end
        end
      end
    end
  end
end
