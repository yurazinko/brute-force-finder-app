# frozen_string_literal: true

class Category < ApplicationRecord
  belongs_to :user, optional: true
  has_many :targets, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
end
