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

  def calculate_counters(time_frame = nil)
    scoped_results = results.by_time_frame(time_frame)
    raw_counts = scoped_results.group(:status).size

    {
      all_clean: scoped_results.where.not(status: :garbage).size,
      unread: raw_counts["unread"] || 0,
      interesting: raw_counts["interesting"] || 0,
      watched: raw_counts["watched"] || 0,
      garbage: raw_counts["garbage"] || 0
    }
  end
end
