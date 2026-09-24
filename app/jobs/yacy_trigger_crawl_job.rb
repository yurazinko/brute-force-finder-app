# frozen_string_literal: true

class YacyTriggerCrawlJob < ApplicationJob
  CRAWL_LOCK_TTL = 3.hours.to_i

  def perform(target_site, collection = "default", options = {})
    options = options.symbolize_keys
    crawl_query_urls = options.fetch(:crawl_query_urls, false)

    lock_key = "yacy:crawling_lock:#{target_site}"

    acquired = Sidekiq.redis do |conn|
      conn.set(lock_key, "in_progress", ex: CRAWL_LOCK_TTL, nx: true)
    end

    return unless acquired

    url = target_site.start_with?("http") ? target_site : "https://#{target_site}"

    SearchEngines::Yacy::Api::Crawler.search(
      url,
      depth: 5,
      max_pages: 200,
      collection: collection,
      crawl_query_urls: crawl_query_urls
    )
  end
end
