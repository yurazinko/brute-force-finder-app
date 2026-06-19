# frozen_string_literal: true

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
