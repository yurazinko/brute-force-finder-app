# frozen_string_literal: true

# == Schema Information
#
# Table name: targets
#
#  id                  :bigint           not null, primary key
#  allow_query_strings :boolean          default(FALSE), not null
#  domain              :string
#  is_active           :boolean          default(TRUE)
#  name                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  category_id         :bigint           not null
#
# Indexes
#
#  index_targets_on_category_id  (category_id)
#  index_targets_on_domain       (domain)
#
# Foreign Keys
#
#  fk_rails_...  (category_id => categories.id)
#
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
