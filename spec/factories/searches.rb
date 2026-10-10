# frozen_string_literal: true

# == Schema Information
#
# Table name: searches
#
#  id                :bigint           not null, primary key
#  query_conditions  :text
#  show_acknowledged :boolean          default(FALSE), not null
#  status            :string           default("pending")
#  time_frame        :string
#  title             :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :bigint
#
# Indexes
#
#  index_searches_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :search do
    association :user
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
