# frozen_string_literal: true

require "rails_helper"

RSpec.describe YacyTriggerCrawlJob, type: :job do
  let(:target_site) { "example.com" }
  let(:collection) { "custom_collection" }
  let(:lock_key) { "yacy:crawling_lock:#{target_site}" }

  before do
    Sidekiq.redis { |conn| conn.del(lock_key) }
    allow(SearchEngines::Yacy::Api::Crawler).to receive(:search)
  end

  after do
    Sidekiq.redis { |conn| conn.del(lock_key) }
  end

  describe "#perform" do
    context "when lock is not acquired (first run)" do
      it "acquires lock in Redis with TTL and triggers crawler search" do
        described_class.new.perform(target_site, collection)

        expect(SearchEngines::Yacy::Api::Crawler).to have_received(:search).with(
          "https://example.com",
          depth: 3,
          max_pages: 200,
          collection: collection,
          crawl_query_urls: false
        )

        lock_exists = Sidekiq.redis { |conn| conn.get(lock_key) }
        expect(lock_exists).to eq("in_progress")
      end

      it "correctly formats URL if HTTP scheme is already present" do
        http_site = "http://my-site.org"
        http_lock_key = "yacy:crawling_lock:#{http_site}"

        described_class.new.perform(http_site)

        expect(SearchEngines::Yacy::Api::Crawler).to have_received(:search).with(
          "http://my-site.org",
          depth: 3,
          max_pages: 200,
          collection: "default",
          crawl_query_urls: false
        )

        Sidekiq.redis { |conn| conn.del(http_lock_key) }
      end

      it "respects crawl_query_urls option when provided" do
        described_class.new.perform(target_site, collection, crawl_query_urls: true)

        expect(SearchEngines::Yacy::Api::Crawler).to have_received(:search).with(
          "https://example.com",
          depth: 3,
          max_pages: 200,
          collection: collection,
          crawl_query_urls: true
        )
      end
    end

    context "when lock is already acquired (duplicate run within TTL)" do
      before do
        Sidekiq.redis do |conn|
          conn.set(lock_key, "in_progress", ex: YacyTriggerCrawlJob::CRAWL_LOCK_TTL, nx: true)
        end
      end

      it "does not trigger crawler search if lock acquisition fails" do
        described_class.new.perform(target_site, collection)

        expect(SearchEngines::Yacy::Api::Crawler).not_to have_received(:search)
      end
    end
  end
end
