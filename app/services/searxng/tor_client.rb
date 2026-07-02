# frozen_string_literal: true

require "httparty"

module Searxng
  class TorClient
    include HTTParty

    base_uri ENV.fetch("SEARXNG_URL", "http://localhost:8080")
    default_timeout 15

    def self.search(query, options = {}) = new(query, options).execute

    def initialize(query, options = {})
      @query = query
      @time_range = options[:time_range]
    end

    def execute
      return { success: true, data: [] } if @query.blank?

      response = self.class.get("/search", query_options)
      handle_response(response)
    rescue HTTParty::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      log_and_return("Network unreachable (Tor/SearXNG dead?): #{e.message}")
    rescue Timeout::Error
      log_and_return("SearXNG gateway timeout")
    rescue StandardError => e
      log_and_return("Unexpected internal client error: #{e.message}")
    end

    private

    def handle_response(response)
      if response.code == 200
        parse_urls(response.body)
      else
        { success: false, error: "SearXNG returned HTTP #{response.code}" }
      end
    end

    def query_options
      base_params = {
        q: @query, format: "json", pageno: 1,
        engines: "google,duckduckgo,bing,brave,qwant,yahoo"
      }
      base_params[:time_range] = @time_range if @time_range.present?

      {
        headers: { "User-Agent" => "BruteForceFinderApp/1.0 (Ruby on Rails; Scraping Pipeline)" },
        query: base_params
      }
    end

    def parse_urls(response_body)
      data = JSON.parse(response_body)
      Rails.logger.info(data)

      return { success: false, error: "SearXNG Engine Error: #{data['error']}" } if data["error"]

      { success: true, data: extract_results(data), failed_engines: data["unresponsive_engines"] || [] }
    rescue JSON::ParserError => e
      log_and_return("Malformed JSON response (Engine blocked or bad proxy config)", e.message)
    end

    def extract_results(data)
      raw_results = data["results"] || []
      filtered = raw_results.map { |hash| hash.slice("url", "title", "content") }
      filtered.uniq { |hash| hash["url"] }
    end

    def log_and_return(error_msg, details = nil)
      full_msg = details ? "#{error_msg}: #{details}" : error_msg
      Rails.logger.error("[Searxng::TorClient] #{full_msg}")
      { success: false, error: error_msg }
    end
  end
end
