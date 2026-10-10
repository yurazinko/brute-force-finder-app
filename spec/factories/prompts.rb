# frozen_string_literal: true

# == Schema Information
#
# Table name: prompts
#
#  id              :bigint           not null, primary key
#  error_message   :text
#  full_query_text :string           not null
#  status          :string           default("pending")
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  search_id       :bigint           not null
#  target_id       :bigint
#
# Indexes
#
#  index_global_prompts_on_search_and_query  (search_id,full_query_text) UNIQUE WHERE (target_id IS NULL)
#  index_prompts_on_search_id                (search_id)
#  index_prompts_on_search_target_and_query  (search_id,target_id,full_query_text) UNIQUE WHERE (target_id IS NOT NULL)
#  index_prompts_on_target_id                (target_id)
#
# Foreign Keys
#
#  fk_rails_...  (search_id => searches.id)
#  fk_rails_...  (target_id => targets.id)
#
FactoryBot.define do
  factory :prompt do
    association :search
    association :target

    status { "pending" }
    error_message { nil }

    sequence(:full_query_text) { |n| "site:#{target.domain} developer remote #{n}" }

    trait :active do
      status { "active" }
    end

    trait :success do
      status { "success" }
    end

    trait :failed do
      status { "failed" }
      error_message { "SearXNG: 429 Too Many Requests" }
    end
  end
end
