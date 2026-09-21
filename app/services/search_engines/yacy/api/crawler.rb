# frozen_string_literal: true

require "public_suffix"
require "ipaddr"

module SearchEngines
  module Yacy
    module Api
      class Crawler < BaseApiClient # rubocop:disable Metrics/ClassLength
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

        def provider_name = "YaCy Crawler"

        def logger_tag = "[YACY_CRAWLER]"

        def perform_request(instance)
          response = self.class.post(
            "#{instance}#{CRAWLER_ENDPOINT}",
            body: build_crawler_params,
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

        def build_crawler_params
          base_crawler_params.tap do |params|
            params["range"] = @options[:range] if @options[:range].present?
            params.merge!(deletion_params) if %w[domain subpath].include?(@options[:range])
            params["sitemapURL"] = @options[:sitemap_url] if @options[:mode] == "sitemap"
          end
        end

        def base_crawler_params # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
          {
            "crawlingstart" => "Neuen Crawl starten",
            "crawlingMode" => @options[:mode] || "url",
            "crawlingURL" => @query,
            "crawlingDepth" => (@options[:depth] || 3).to_s,
            "mustmatch" => resolve_mustmatch,
            "mustnotmatch" => @options[:mustnotmatch] || "",
            "crawlingQ" => @options[:crawl_query_urls] ? "on" : "off",
            "crawlingDomMaxPages" => (@options[:max_pages] || 100).to_s,
            "recrawl" => @options[:recrawl] || "nodoubles",
            "reloadIfOlderNumber" => (@options[:reload_older_num] || 1).to_s,
            "reloadIfOlderUnit" => @options[:reload_older_unit] || "day",
            "indexText" => @options[:index_text] == false ? "off" : "on",
            "indexMedia" => @options[:index_media] ? "on" : "off",
            "xsstopw" => @options[:use_stopwords] == false ? "off" : "on",
            "collection" => @options[:collection] || "default",
            "crawlOrder" => "off",
            "agentName" => @options[:agent_name] || "YaCy Internet (cautious)"
          }
        end

        def deletion_params
          {
            "deleteold" => "age",
            "deleteIfOlderNumber" => (@options[:delete_older_num] || 14).to_s,
            "deleteIfOlderUnit" => @options[:delete_older_unit] || "day"
          }
        end

        def resolve_mustmatch
          return @options[:mustmatch] if @options[:mustmatch].present?
          return ".*" if %w[domain subpath].include?(@options[:range])

          extract_domain_pattern(@query)
        end

        def extract_domain_pattern(url_string)
          host = parse_host(url_string)
          return ".*" if host.blank?

          clean_host = host.tr("[]", "")
          return ".*://#{Regexp.escape(host)}(?::\\d+)?(?:/.*)?$" if valid_ip?(clean_host)
          return ".*://localhost(?::\\d+)?(?:/.*)?$" if clean_host == "localhost"

          format_domain_pattern(clean_host)
        rescue URI::InvalidURIError, PublicSuffix::DomainInvalid, PublicSuffix::Error
          ".*"
        end

        def parse_host(url_string)
          URI.parse(url_string.to_s.start_with?("http") ? url_string.to_s : "http://#{url_string}").host&.downcase
        end

        def format_domain_pattern(clean_host)
          parsed_domain = PublicSuffix.parse(clean_host, ignore_private: true)
          domain = parsed_domain.domain.presence || clean_host

          ".*://(?:[^/]+\\.)?#{Regexp.escape(domain)}(?::\\d+)?(?:/.*)?$"
        end

        def valid_ip?(host)
          IPAddr.new(host)
          true
        rescue IPAddr::Error
          false
        end

        def auth_credentials
          { username: ENV.fetch("YACY_ADMIN_USER", "admin"),
            password: ENV.fetch("YACY_ADMIN_PASSWORD", "yacy") }
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
