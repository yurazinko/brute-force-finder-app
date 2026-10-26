# frozen_string_literal: true

class TargetActivationJob < ApplicationJob
  include Sidekiq::Job

  sidekiq_options queue: :search_activations, retry: 3

  def perform(target_id, search_ids, user_id = nil)
    target = Target.find_by(id: target_id)
    return unless target

    user = find_user(target, user_id)
    return unless user

    searches = fetch_searches(user, search_ids)
    synchronize_prompts!(target, searches)
  end

  private

  def find_user(target, user_id)
    User.find_by(id: user_id) || target.category.user
  end

  def fetch_searches(user, search_ids)
    requested_ids = Array(search_ids).compact_blank.map(&:to_s)
    user.searches.where(id: requested_ids.uniq)
  end

  def synchronize_prompts!(target, searches)
    ActiveRecord::Base.transaction do
      target.prompts.where.not(search_id: searches.select(:id)).destroy_all

      searches.find_each do |search|
        target.prompts.find_or_create_by!(search: search) do |prompt|
          prompt.full_query_text = "site:#{target.domain} #{search.query_conditions}"
        end
      end
    end
  end
end
