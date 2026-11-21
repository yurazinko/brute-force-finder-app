# frozen_string_literal: true

class QuickSearchJob < ApplicationJob
  sidekiq_options queue: :scraping, retry: 0

  def perform(token, user_id)
    QuickSearch::Runner.new(token: token, user_id: user_id).call
  end
end
