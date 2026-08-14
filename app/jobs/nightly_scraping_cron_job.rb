# frozen_string_literal: true

class NightlyScrapingCronJob < ApplicationJob
  sidekiq_options queue: :default, retry: false

  def perform
    Rails.logger.info("[Cron] Nightly scraping pipeline started.")

    searches_data = ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT id, user_id
      FROM searches
      WHERE status IN ('completed', 'pending', 'failed')
    SQL

    searches_data.shuffle.each_with_index do |(search_id, user_id), index|
      campaign_delay = (index * 20) + rand(30..45)
      SearchActivationJob.perform_in(campaign_delay.minutes, search_id, user_id)
    end
  end
end
