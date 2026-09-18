# frozen_string_literal: true

class YacyTriggerCrawlJob < ApplicationJob
  CRAWL_LOCK_TTL = 6.hours.to_i

  def perform(target_site, collection = "default")
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://redis:6379/1"))
    lock_key = "yacy:crawling_lock:#{target_site}"

    return if redis.exists?(lock_key)

    redis.setex(lock_key, CRAWL_LOCK_TTL, "in_progress")

    url = target_site.start_with?("http") ? target_site : "https://#{target_site}"

    SearchEngines::Yacy::Api::Crawler.search(
      url,
      depth: 2,
      max_pages: 50,
      range: "domain",
      collection: collection
    )
  end
end
