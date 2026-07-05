# frozen_string_literal: true

class NightlyScrapingCronJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: false

  def perform
    Rails.logger.info("[Cron] Nightly scraping pipeline started.")

    searches = Search.where(status: %w[completed pending failed]) #  TODO Add flag to toggle nightly run for Search

    searches.shuffle.each_with_index do |search, index|
      campaign_delay = (index * 20) + rand(30..45)

      SearchActivationJob.perform_in(campaign_delay.minutes, search.id)
    end
  end
end
