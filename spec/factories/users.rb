# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { "#{SecureRandom.uuid}@mail.com" }
    password { "password123" }
  end
end
