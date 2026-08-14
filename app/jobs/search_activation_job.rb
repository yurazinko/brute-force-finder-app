# frozen_string_literal: true

class SearchActivationJob < ApplicationJob
  sidekiq_options queue: :search_activations, retry: false

  def perform(search_id, _user_id)
    search = Search.find_by(id: search_id)
    return unless search

    target_ids = search.targets.active.pluck(:id)
    SearchCampaigns::Activator.call(search, target_ids)
  end
end
