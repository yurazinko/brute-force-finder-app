# frozen_string_literal: true

class SearchActivationJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: false

  def perform(search_id)
    search = Search.find_by(id: search_id)
    return unless search

    target_ids = search.targets.active.pluck(:id)
    return if target_ids.blank?

    SearchCampaigns::Activator.call(search, target_ids)
  end
end
