# frozen_string_literal: true

class Search < ApplicationRecord
  has_many :prompts, dependent: :destroy
  has_many :targets, through: :prompts
  has_many :results, dependent: :destroy

  validates :title, :query_conditions, presence: true
  validates :status, inclusion: { in: %w[pending processing completed] }

  validates :time_frame, inclusion: { in: [nil, "day", "week", "month", "year"] }, allow_nil: true

  def activate_search!(target_ids)
    SearchActivator.call(self, target_ids)
  end
end
