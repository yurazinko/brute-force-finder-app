# frozen_string_literal: true

class NightlyScrapingCronJob < ApplicationJob
  include Rls::Context

  sidekiq_options queue: :default, retry: false

  def perform
    Rails.logger.info("[Cron] Nightly scraping pipeline started.")

    schedule_searches(collect_all_searches)
  end

  private

  def collect_all_searches
    searches = []
    User.in_batches(of: 500).each_record do |user|
      with_rls_user(user.id) do
        searches.concat(fetch_user_searches)
      end
    end
    searches
  end

  def fetch_user_searches
    ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT id, user_id
      FROM searches
      WHERE status IN ('completed', 'pending', 'failed')
    SQL
  end

  def schedule_searches(searches)
    searches.shuffle.each_with_index do |(search_id, user_id), index|
      campaign_delay = (index * 20) + rand(30..45)
      SearchActivationJob.perform_in(campaign_delay.minutes, search_id, user_id)
    end
  end
end
