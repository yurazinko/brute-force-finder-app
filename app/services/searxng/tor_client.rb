# frozen_string_literal: true

require "httparty"

module Searxng
  class TorClient
    include HTTParty

    base_uri ENV.fetch("SEARXNG_URL", "http://localhost:8080")
    default_timeout 15

    def self.search(query, options = {})
      new(query, options).execute
    end

    def initialize(query, options = {})
      @query = query
      @time_range = options[:time_range]
    end

    def execute
      return { success: true, data: [] } if @query.blank?

      response = self.class.get("/search", query_options)

      return { success: false, error: "SearXNG returned HTTP #{response.code}" } if response.code != 200

      parse_urls(response.body)
    rescue HTTParty::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      error_msg = "Network unreachable (Tor/SearXNG dead?): #{e.message}"
      Rails.logger.error("[Searxng::TorClient] #{error_msg}")
      { success: false, error: error_msg }
    rescue Timeout::Error
      error_msg = "SearXNG gateway timeout"
      Rails.logger.error("[Searxng::TorClient] #{error_msg}")
      { success: false, error: error_msg }
    rescue StandardError => e
      error_msg = "Unexpected internal client error: #{e.message}"
      Rails.logger.error("[Searxng::TorClient] #{error_msg}")
      { success: false, error: error_msg }
    end

    private

    def query_options
      base_params = {
        q: @query,
        format: "json",
        engines: "google,duckduckgo,bing,brave,qwant,yahoo",
        pageno: 1
      }

      base_params[:time_range] = @time_range if @time_range.present?

      {
        headers: { "User-Agent" => "BruteForceFinderApp/1.0 (Ruby on Rails; Scraping Pipeline)" },
        query: base_params
      }
    end

    def parse_urls(response_body)
      data = JSON.parse(response_body)

      return { success: false, error: "SearXNG Engine Error: #{data['error']}" } if data["error"]

      results = data["results"]&.map { |hash| hash.slice("url", "title", "content") } || []
      { success: true, data: results.uniq { |hash| hash["url"] }, failed_engines: data["unresponsive_engines"] || [] }
    rescue JSON::ParserError => e
      error_msg = "Malformed JSON response (Engine blocked or bad proxy config)"
      Rails.logger.error("[Searxng::TorClient] #{error_msg}: #{e.message}")
      { success: false, error: error_msg }
    end
  end
end
