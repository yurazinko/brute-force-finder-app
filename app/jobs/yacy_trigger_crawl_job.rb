# frozen_string_literal: true

class YacyTriggerCrawlJob < ApplicationJob
  CRAWL_LOCK_TTL = 3.hours.to_i

  def perform(target_site, collection = "default", crawl_query_urls: false)
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1"))
    lock_key = "yacy:crawling_lock:#{target_site}"

    return if redis.exists?(lock_key)

    redis.setex(lock_key, CRAWL_LOCK_TTL, "in_progress")

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
