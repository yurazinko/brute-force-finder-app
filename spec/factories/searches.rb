# frozen_string_literal: true

FactoryBot.define do
  factory :search do
    sequence(:title) { |n| "Campaign ##{n}: #{Faker::Marketing.buzzwords}" }
    query_conditions { "developer remote Ruby" }
    status { "pending" }
    time_frame { "week" }

    trait :completed do
      status { "completed" }
    end

    trait :processing do
      status { "processing" }
    end

    trait :failed do
      status { "failed" }
    end
  end
end
