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
      return [] if @query.blank?

      response = self.class.get("/search", query_options)

      raise("Unexpected status code #{response.code}") unless response.code == 200

      parse_urls(response.body)
    rescue StandardError => e
      Rails.logger.error("[Searxng::TorClient] Error: #{e.message}")
      []
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
      results = data["results"]&.map { |hash| hash.slice("url", "title", "content") } || []
      results.uniq { |hash| hash["url"] }
    rescue JSON::ParserError => e
      Rails.logger.error("[Searxng::TorClient] Failed to parse JSON response: #{e.message}")
      []
    end
  end
end
