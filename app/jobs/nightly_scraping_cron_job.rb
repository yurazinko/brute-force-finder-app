# frozen_string_literal: true

class NightlyScrapingCronJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: false

  def perform
    Rails.logger.info("[Cron] Nightly scraping pipeline started.")

    searches = Search.where(status: %w[completed failed]) #  TODO Add flag to toggle nightly run for Search

    searches.each_with_index do |search, index|
      campaign_delay = (index * 20).minutes + rand(10..30).minutes

      sleep(campaign_delay) if Rails.env.development?

      SearchActivationJob.perform_in(campaign_delay, search.id)
    end
  end
end
