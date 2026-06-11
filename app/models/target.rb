# frozen_string_literal: true

class Target < ApplicationRecord
  belongs_to :category
  has_many :prompts, dependent: :destroy

  validates :name, :domain, presence: true
  validates :domain, uniqueness: true

  scope :active, -> { where(is_active: true) }
end
