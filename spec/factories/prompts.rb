# frozen_string_literal: true

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
