# frozen_string_literal: true

class Category < ApplicationRecord
  has_many :targets, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
