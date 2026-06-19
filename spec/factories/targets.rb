# frozen_string_literal: true

FactoryBot.define do
  factory :target do
    association :category

    sequence(:name) { |n| "Target Company #{n}" }
    sequence(:domain) { |n| "company-#{n}-#{Faker::Internet.domain_name}" }
    is_active { true }

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end
  end
end
