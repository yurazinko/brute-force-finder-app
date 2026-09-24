# frozen_string_literal: true

class Category < ApplicationRecord
  belongs_to :user, optional: true

  has_many :targets,
           -> { order(:name) },
           dependent: :destroy,
           inverse_of: :category

  has_many :active_targets,
           -> { active.order(:name) },
           class_name: "Target",
           dependent: nil,
           inverse_of: :category

  validates :name, presence: true, uniqueness: { scope: :user_id }
end
