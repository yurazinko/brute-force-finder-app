# frozen_string_literal: true

class NightlyScrapingCronJob < ApplicationJob
  include Rls::Context

  sidekiq_options queue: :default, retry: false

  BASE_DELAY_MINUTES = 3

  def perform
    Rails.logger.info("[Cron] Nightly scraping pipeline started.")

    index = 0

    User.find_each(batch_size: 100) do |user|
      with_rls_user(user.id) do
        fetch_user_eligible_searches(user.id).each do |search_id|
          schedule_search(search_id, user.id, index)
          index += 1
        end
      end
    end

    Rails.logger.info("[Cron] Nightly scraping pipeline scheduled #{index} searches.")
  end

  private

  def fetch_user_eligible_searches(_user_id)
    Search.where(status: %w[completed pending processing failed]).pluck(:id)
  end

  def schedule_search(search_id, user_id, index)
    delay_minutes = (index * BASE_DELAY_MINUTES) + (rand(30..180) / 60.0)
    SearchActivationJob.perform_in(delay_minutes.minutes, search_id, user_id)
  end
end
