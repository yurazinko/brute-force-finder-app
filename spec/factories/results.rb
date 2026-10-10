# frozen_string_literal: true

# == Schema Information
#
# Table name: results
#
#  id                  :bigint           not null, primary key
#  acknowledged        :boolean          default(FALSE), not null
#  content             :text
#  engine              :string
#  matched_keywords    :jsonb            not null
#  relevance_score     :integer          default(0), not null
#  status              :string           default("unread"), not null
#  title               :string
#  url                 :string           not null
#  url_hash            :string           not null
#  verification_status :string           default("pending"), not null
#  viewed_at           :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  search_id           :bigint           not null
#
# Indexes
#
#  idx_results_analytics                           (search_id,status,acknowledged)
#  idx_results_content_trgm                        (content gin_trgm_ops) USING gin
#  idx_results_title_trgm                          (title gin_trgm_ops) USING gin
#  idx_results_url_trgm                            (url gin_trgm_ops) USING gin
#  index_results_on_relevance_score                (relevance_score)
#  index_results_on_search_id                      (search_id)
#  index_results_on_search_id_and_relevance_score  (search_id,relevance_score)
#  index_results_on_search_id_and_status           (search_id,status)
#  index_results_on_search_id_and_url_hash         (search_id,url_hash) UNIQUE
#  index_results_on_url_hash                       (url_hash)
#  index_results_on_verification_status            (verification_status)
#
# Foreign Keys
#
#  fk_rails_...  (search_id => searches.id)
#
FactoryBot.define do
  factory :result do
    association :search

    sequence(:title) { |n| "Job Opening #{n}: #{Faker::Job.title}" }
    sequence(:url) { |n| "https://#{Faker::Internet.domain_name}/jobs/#{n}" }

    url_hash { Digest::MD5.hexdigest(url) }
    content { Faker::Lorem.paragraph(sentence_count: 5) }
    status { "unread" }
    viewed_at { nil }

    trait :unread do
      status { "unread" }
    end

    trait :interesting do
      status { "interesting" }
    end

    trait :watched do
      status { "watched" }
    end

    trait :garbage do
      status { "garbage" }
    end

    trait :viewed do
      status { "unread" }
      viewed_at { Time.current }
    end
  end
end
